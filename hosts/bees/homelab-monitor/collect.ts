#!/usr/bin/env bun
//
// Homelab Infrastructure Monitor
//
// Collects metrics from Prometheus, logs via SSH, and uses pi (AI)
// to analyze the data and surface issues via ntfy.
//
// Usage: bun collect.ts [check|daily|report]
//   check  — 3-hourly critical check (alerts only if issues found)
//   daily  — comprehensive daily report (always sent via ntfy)
//   report — on-demand report printed to stdout

import { readFileSync, writeFileSync, unlinkSync } from "node:fs";
import { join } from "node:path";

// ── Configuration ──────────────────────────────────────────────────
const PROM_URL = "http://localhost:9090";
const NTFY_URL = "http://localhost:8090";
const NTFY_TOPIC = "homelab-monitor";
const PROMPT_FILE = "/etc/homelab-monitor/system-prompt.md";
const SSH_OPTS = [
  "-o", "IdentitiesOnly=yes",
  "-o", "ConnectTimeout=5",
  "-o", "StrictHostKeyChecking=accept-new",
  "-o", "BatchMode=yes",
];

// ── Mode & time range ─────────────────────────────────────────────
const mode = Bun.argv[2] || "check";
const { hours, range } =
  mode === "daily"  ? { hours: 24, range: "24h" } :
  mode === "report" ? { hours: 6,  range: "6h" }  :
                      { hours: 3,  range: "3h" };

// ── Logging ────────────────────────────────────────────────────────
const log = (msg: string) =>
  console.error(`[${new Date().toLocaleTimeString("en-US", { hour12: false })}] ${msg}`);

// ════════════════════════════════════════════════════════════════════
// Prometheus helpers (uses fetch — no curl/jq needed)
// ════════════════════════════════════════════════════════════════════

async function promQuery(query: string): Promise<any[]> {
  try {
    const resp = await fetch(`${PROM_URL}/api/v1/query`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: `query=${encodeURIComponent(query)}`,
    });
    return ((await resp.json()) as any)?.data?.result ?? [];
  } catch {
    return [];
  }
}

async function promVal(query: string): Promise<string> {
  const v = (await promQuery(query))?.[0]?.value?.[1];
  if (!v || v === "NaN" || v === "+Inf" || v === "-Inf") return "N/A";
  const n = parseFloat(v);
  return isNaN(n) ? v : n.toFixed(1);
}

async function promLabeled(query: string, label: string): Promise<string[]> {
  const results = await promQuery(query);
  return results.length
    ? results.map((r: any) => `  ${r.metric[label]}: ${r.value[1]}`)
    : ["  N/A"];
}

// ════════════════════════════════════════════════════════════════════
// SSH helpers (async for concurrent collection)
// ════════════════════════════════════════════════════════════════════

async function ssh(userHost: string, command: string): Promise<string> {
  try {
    const proc = Bun.spawn(["ssh", ...SSH_OPTS, userHost, command], {
      stdout: "pipe",
      stderr: "pipe",
    });
    const [exitCode, text] = await Promise.all([
      proc.exited,
      new Response(proc.stdout).text(),
    ]);
    return exitCode === 0 ? text.trim() : "(SSH failed)";
  } catch {
    return "(SSH failed)";
  }
}

async function reachable(userHost: string): Promise<boolean> {
  try {
    const proc = Bun.spawn(["ssh", ...SSH_OPTS, userHost, "echo ok"], {
      stdout: "pipe",
      stderr: "pipe",
    });
    return (await proc.exited) === 0;
  } catch {
    return false;
  }
}

// ════════════════════════════════════════════════════════════════════
// Host definitions
// ════════════════════════════════════════════════════════════════════

const PROM_HOSTS = [
  { name: "bees",  inst: "localhost:9100" },
  { name: "bee",   inst: "10.10.0.12:9100" },
  { name: "think", inst: "10.10.0.10:9100" },
];

interface RemoteHost {
  name: string;
  userHost: string;
  offlineNote?: string;
  commands: Record<string, string>;
}

const REMOTE_HOSTS: RemoteHost[] = [
  {
    name: "bee",
    userHost: "crussell@10.10.0.12",
    commands: {
      "Failed systemd units": "systemctl --failed --no-pager 2>/dev/null | head -20",
      "User service failures": "XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user --failed --no-pager 2>/dev/null | head -20",
      [`Journal errors (last ${hours}h)`]: `journalctl -p err --since '${hours} hours ago' --no-pager -q 2>/dev/null | tail -40`,
      "Memory & Disk": "free -h; echo '---'; df -h / /mnt/backups 2>/dev/null",
    },
  },
  {
    name: "think",
    userHost: "crussell@10.10.0.10",
    offlineNote: "**Host unreachable** (expected if sleeping/offline)",
    commands: {
      [`Journal errors (last ${hours}h)`]: `journalctl -p err --since '${hours} hours ago' --no-pager -q 2>/dev/null | tail -30`,
      "Memory & Disk": "free -h; echo '---'; df -h /",
    },
  },
  {
    name: "nas",
    userHost: "root@10.10.0.3",
    commands: {
      "System status": "uptime; echo '---'; free -h; echo '---'; df -h",
      "ZFS Pool Status": "zpool status 2>/dev/null || echo 'zpool not available'",
    },
  },
  {
    name: "gateway",
    userHost: "root@10.10.0.2",
    commands: {
      "System status": "uptime; echo '---'; free -h; echo '---'; df -h",
      "Service status (nginx, nebula)": "systemctl is-active nginx nebula 2>/dev/null",
      [`Journal errors (last ${hours}h)`]: `journalctl -p err --since '${hours} hours ago' --no-pager -q 2>/dev/null | tail -30`,
    },
  },
];

// ════════════════════════════════════════════════════════════════════
// Data collection
// ════════════════════════════════════════════════════════════════════

async function collectPrometheus(): Promise<string> {
  log("Collecting Prometheus metrics...");
  const sections = await Promise.all(
    PROM_HOSTS.map(async ({ name, inst }) => {
      const [cpu, mem, load, uptime, fs] = await Promise.all([
        promVal(`100 - (avg(rate(node_cpu_seconds_total{mode="idle",instance="${inst}"}[${range}])) * 100)`),
        promVal(`(1 - node_memory_MemAvailable_bytes{instance="${inst}"} / node_memory_MemTotal_bytes{instance="${inst}"}) * 100`),
        promVal(`node_load1{instance="${inst}"}`),
        promVal(`(time() - node_boot_time_seconds{instance="${inst}"}) / 3600`),
        promLabeled(
          `(1 - node_filesystem_avail_bytes{instance="${inst}",fstype!~"tmpfs|overlay|squashfs|nsfs"} / node_filesystem_size_bytes{instance="${inst}",fstype!~"tmpfs|overlay|squashfs|nsfs"}) * 100`,
          "mountpoint",
        ),
      ]);
      const fsLines = fs.map(l => l === "  N/A" ? l : `${l}%`).join("\n");
      return [
        `### ${name} (${inst})`,
        "",
        `CPU usage: ${cpu}%`,
        `Memory usage: ${mem}%`,
        `Load (1m): ${load}`,
        `Uptime: ${uptime}h`,
        "Filesystems:",
        fsLines,
        "",
      ].join("\n");
    }),
  );
  return `## Prometheus Metrics (node_exporter)\n\n${sections.join("\n")}`;
}

async function collectNetwork(): Promise<string> {
  const lines = await Promise.all(
    PROM_HOSTS.map(async ({ name, inst }) => {
      const [rx, tx] = await Promise.all([
        promVal(`sum(rate(node_network_receive_bytes_total{instance="${inst}",device!~"lo|docker.*|br-.*|veth.*"}[${range}]))`),
        promVal(`sum(rate(node_network_transmit_bytes_total{instance="${inst}",device!~"lo|docker.*|br-.*|veth.*"}[${range}]))`),
      ]);
      return `  ${name} — RX: ${rx} B/s, TX: ${tx} B/s`;
    }),
  );
  return `### Network Traffic (avg bytes/sec over ${range})\n${lines.join("\n")}\n`;
}

function localOutput(args: string[]): string {
  try {
    const proc = Bun.spawnSync(args, { stdout: "pipe", stderr: "pipe" });
    return proc.stdout?.toString().trim() ?? "";
  } catch {
    return "";
  }
}

function collectBeesLocal(): string {
  log("Collecting bees local logs...");
  const failed = localOutput(["systemctl", "--failed", "--no-pager"]);
  const journal = localOutput(["journalctl", "-p", "err", "--since", `${hours} hours ago`, "--no-pager", "-q"]);
  const dmesg = localOutput(["dmesg", "-l", "err,warn"]);

  return [
    "## bees — Local Logs & Status",
    "",
    "### Failed systemd units",
    failed.split("\n").slice(0, 20).join("\n") || "(none)",
    "",
    `### Journal errors (last ${hours}h, last 50 lines)`,
    journal.split("\n").slice(-50).join("\n") || "(none)",
    "",
    "### dmesg errors/warnings (last 20)",
    dmesg.split("\n").slice(-20).join("\n") || "(none)",
    "",
  ].join("\n");
}

async function collectRemote({ name, userHost, commands, offlineNote }: RemoteHost): Promise<string> {
  log(`Collecting ${name} remote data...`);
  if (!await reachable(userHost)) {
    return `## ${name} — Remote Data (SSH)\n\n${offlineNote ?? "**Host unreachable**"}\n`;
  }
  const sections = await Promise.all(
    Object.entries(commands).map(async ([heading, cmd]) =>
      [`### ${heading}`, await ssh(userHost, cmd), ""].join("\n")
    ),
  );
  return `## ${name} — Remote Data (SSH)\n\n${sections.join("\n")}`;
}

// ════════════════════════════════════════════════════════════════════
// AI analysis
// ════════════════════════════════════════════════════════════════════

const INSTRUCTIONS: Record<string, string> = {
  daily: [
    "MODE: DAILY REPORT",
    "",
    "Analyze the infrastructure data and produce a daily health report for every machine.",
    'For each machine, give a one-line status summary with emoji (✅ healthy, ⚠️ warning, ❌ critical), then brief notes on anything notable. End with an "Action Items" section if anything needs attention.',
    "Keep the entire report under 3000 characters. Do not include this instruction in your output.",
  ].join("\n"),

  report: [
    "MODE: ON-DEMAND REPORT",
    "",
    "Analyze the infrastructure data and produce a comprehensive health report for every machine.",
    'For each machine, give a one-line status summary with emoji (✅ healthy, ⚠️ warning, ❌ critical), then brief notes on anything notable. Include metrics summaries (CPU, memory, disk) where available. End with an "Action Items" section if anything needs attention.',
    "Keep the entire report under 4000 characters. Do not include this instruction in your output.",
  ].join("\n"),

  check: [
    "MODE: CRITICAL CHECK",
    "",
    "Analyze the infrastructure data for critical issues only.",
    "If everything is operating normally with no issues requiring attention, respond with exactly the single word ALL_CLEAR and nothing else.",
    "If there are critical issues needing immediate attention, start with CRITICAL_ALERT: and list only the problems.",
    "Keep it under 1000 characters. Do not include this instruction in your output.",
  ].join("\n"),
};

function runAnalysis(data: string): string | null {
  const systemPrompt = (() => {
    try { return readFileSync(PROMPT_FILE, "utf-8"); }
    catch { return ""; }
  })();
  const instruction = INSTRUCTIONS[mode] ?? INSTRUCTIONS.check;

  const tmpPath = join("/tmp", `homelab-data-${Date.now()}.md`);
  writeFileSync(tmpPath, data);

  try {
    const proc = Bun.spawnSync([
      "pi", "-p", "-nt", "--no-session", "-ne", "-ns", "-nc",
      "--system-prompt", systemPrompt,
      `@${tmpPath}`,
      instruction,
    ], { stdout: "pipe", stderr: "pipe" });

    return proc.exitCode === 0 ? proc.stdout.toString().trim() : null;
  } finally {
    try { unlinkSync(tmpPath); } catch {}
  }
}

// ════════════════════════════════════════════════════════════════════
// Notification
// ════════════════════════════════════════════════════════════════════

async function sendNtfy(title: string, priority: string, tags: string, body: string) {
  const finalBody = Buffer.byteLength(body) > 4000
    ? body.slice(0, 3900) + "\n[Report truncated. Full output in: journalctl -u homelab-monitor-${mode}]"
    : body;
  try {
    await fetch(`${NTFY_URL}/${NTFY_TOPIC}`, {
      method: "POST",
      headers: { Title: title, Priority: priority, Tags: tags },
      body: finalBody,
    });
  } catch {}
}

// ════════════════════════════════════════════════════════════════════
// Main
// ════════════════════════════════════════════════════════════════════

async function main() {
  log(`Starting homelab monitor (mode=${mode}, period=${hours}h)`);

  // All collection runs concurrently: Prometheus via fetch, SSH via async spawn
  const [promMetrics, network, beesLocal, ...remoteData] = await Promise.all([
    collectPrometheus(),
    collectNetwork(),
    Promise.resolve(collectBeesLocal()),
    ...REMOTE_HOSTS.map(h => collectRemote(h)),
  ]);

  const data = [
    "# Homelab Infrastructure Data",
    `# Mode: ${mode} | Period: last ${hours}h | Generated: ${new Date().toISOString()}`,
    "",
    "## Machine Overview",
    "- bees (10.10.0.6): Production — Caddy, Jellyfin, Immich, ntfy, SearXNG, linkding, papra, open-webui, media services",
    "- bee (10.10.0.12): Dev — Gloo stack, Nebula lighthouse",
    "- think (10.10.0.10): Laptop — may be offline",
    "- nas (10.10.0.3): TrueNAS — NFS storage",
    "- gateway (10.10.0.2): Hetzner VPS — Caddy public TLS ingress (*.crussell.io, HTTP-01) → backends over Nebula; Nebula relay/lighthouse",
    "",
    promMetrics,
    network,
    beesLocal,
    ...remoteData,
  ].join("\n");

  log(`Collected ${Buffer.byteLength(data)} bytes of data`);

  // AI analysis
  log("Running pi analysis...");
  const report = runAnalysis(data);
  if (!report) {
    log("ERROR: pi analysis failed");
    if (mode !== "report") {
      await sendNtfy(
        "⚠️ Homelab Monitor Error", "high", "warning",
        `Monitor failed to generate report (pi exited non-zero). Check: journalctl -u homelab-monitor-${mode}`,
      );
    }
    process.exit(1);
  }
  log(`AI report generated: ${Buffer.byteLength(report)} bytes`);

  // Output
  if (mode === "report") {
    log("Report mode — printing to stdout");
    console.log(report);
  } else if (mode === "check") {
    if (report.includes("ALL_CLEAR")) {
      log("All clear — no notification sent");
    } else {
      log("Issues detected — sending alert");
      await sendNtfy("⚠️ Homelab Alert", "high", "warning", report);
    }
  } else {
    log("Sending daily report");
    await sendNtfy(
      `☀️ Daily Homelab Report — ${new Date().toISOString().slice(0, 10)}`,
      "low", "clipboard", report,
    );
  }

  log("Done");
}

main().catch(e => {
  log(`Fatal: ${e.message}`);
  process.exit(1);
});

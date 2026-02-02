#!/usr/bin/env bun

import { readFile } from "node:fs/promises";
import path from "node:path";

type CmdResult = {
  ok: boolean;
  code: number;
  stdout: string;
  stderr: string;
};

type SnapshotInfo = {
  ok: boolean;
  id?: string;
  time?: string;
  age_hours?: number;
  stale?: boolean;
  paths?: string[];
  error?: string;
};

type NodeReport = {
  ip: string;
  hostname: string | null;
  jobs: string[];
  checks: Record<string, any>;
  snapshots: Record<string, SnapshotInfo>;
  issues: string[];
};

const NODES: Record<string, string> = {
  k2: "192.168.20.62",
  k3: "192.168.20.63",
  k4: "192.168.20.64",
};

const NAS_IP = process.env.NAS_IP ?? "192.168.20.31";
const SSH_KEY = process.env.SSH_KEY ?? "~/.ssh/id_ed25519";

const REPO = "/mnt/backups/restic";
const PASS_FILE = "/etc/restic-password";
const RESTIC_BIN = "/run/current-system/sw/bin/restic";

// threshold: backups should be within ~36h (03:00 + jitter + lock retries)
const STALE_HOURS = 36;

function expandHome(p: string): string {
  if (p === "~") return process.env.HOME ?? p;
  if (p.startsWith("~/")) return path.join(process.env.HOME ?? "", p.slice(2));
  return p;
}

async function run(cmd: string[], timeoutMs: number): Promise<CmdResult> {
  const proc = Bun.spawn(cmd, {
    stdout: "pipe",
    stderr: "pipe",
  });

  const timer = setTimeout(() => {
    try {
      proc.kill("SIGKILL");
    } catch {
      // ignore
    }
  }, timeoutMs);

  const [stdoutBuf, stderrBuf, exitCode] = await Promise.all([
    new Response(proc.stdout).arrayBuffer(),
    new Response(proc.stderr).arrayBuffer(),
    proc.exited,
  ]).finally(() => clearTimeout(timer));

  const stdout = Buffer.from(stdoutBuf).toString("utf8");
  const stderr = Buffer.from(stderrBuf).toString("utf8");

  return {
    ok: exitCode === 0,
    code: exitCode,
    stdout,
    stderr,
  };
}

async function ssh(userAtIp: string, remoteCmd: string, timeoutMs = 120_000): Promise<CmdResult> {
  const key = expandHome(SSH_KEY);
  const cmd = [
    "ssh",
    "-i",
    key,
    "-o",
    "BatchMode=yes",
    "-o",
    "StrictHostKeyChecking=accept-new",
    userAtIp,
    remoteCmd,
  ];
  return run(cmd, timeoutMs);
}

async function loadJobs(cfgPath: string): Promise<string[]> {
  const raw = await readFile(cfgPath, "utf8");
  const data = JSON.parse(raw);
  const jobs = Array.isArray(data?.jobs) ? data.jobs : [];
  return jobs.map((j: any) => j?.name).filter((n: any) => typeof n === "string" && n.length > 0);
}

function parseResticTime(s: string | undefined): Date | null {
  if (!s) return null;
  // restic returns RFC3339 timestamps like 2026-02-02T19:32:21Z
  const t = s.endsWith("Z") ? s.slice(0, -1) + "+00:00" : s;
  const d = new Date(t);
  return isNaN(d.getTime()) ? null : d;
}

async function main(): Promise<number> {
  const repoRoot = path.resolve(import.meta.dir, "..");
  const cfgDir = path.join(repoRoot, "backups", "restic");
  const now = new Date();
  const nowUtcMs = now.getTime();

  const report: any = {
    generated_at: new Date(nowUtcMs).toISOString(),
    repo: REPO,
    thresholds: { snapshot_stale_hours: STALE_HOURS },
    nas: {
      ip: NAS_IP,
      checks: {},
      issues: [] as string[],
    },
    nodes: {},
  };

  // NAS checks (run on NAS directly)
  {
    const nasUserAtIp = `root@${NAS_IP}`;
    const host = await ssh(nasUserAtIp, "hostname");
    report.nas.hostname = host.ok ? host.stdout.trim() : null;

    // Confirm expected backup share + restic repo exist on NAS
    // Your NFS export is /mnt/tank/backups; restic repo should be /mnt/tank/backups/restic
    const repoCheck = await ssh(
      nasUserAtIp,
      "test -f /mnt/tank/backups/restic/config && echo OK || echo MISSING",
    );
    report.nas.checks.repo_present = { ok: repoCheck.ok && repoCheck.stdout.trim() === "OK", out: repoCheck.stdout.trim(), err: repoCheck.stderr.trim() };
    if (!report.nas.checks.repo_present.ok) report.nas.issues.push("repo_missing_on_nas");

    const df = await ssh(nasUserAtIp, "df -h /mnt/tank/backups | tail -n 1", 60_000);
    report.nas.checks.free_space = { ok: df.ok, out: df.stdout.trim(), err: df.stderr.trim() };
  }

  for (const [node, ip] of Object.entries(NODES)) {
    const cfgPath = path.join(cfgDir, `${node}.json`);
    const jobs = await loadJobs(cfgPath).catch(() => []);

    const nodeReport: NodeReport = {
      ip,
      hostname: null,
      jobs,
      checks: {},
      snapshots: {},
      issues: [],
    };

    const userAtIp = `crussell@${ip}`;

    const host = await ssh(userAtIp, "hostname");
    nodeReport.hostname = host.ok ? host.stdout.trim() : null;

    // Password file existence/perms (do not print contents)
    const pw = await ssh(userAtIp, `sudo test -f ${PASS_FILE} && sudo stat -c '%a %U:%G' ${PASS_FILE}`);
    nodeReport.checks.password_file = pw.ok ? { ok: true, stat: pw.stdout.trim() } : { ok: false, error: (pw.stderr.trim() || pw.stdout.trim()) };
    if (!pw.ok) nodeReport.issues.push("missing_or_unreadable_password_file");

    // NFS mount + repo presence
    const nfs = await ssh(userAtIp, "mountpoint -q /mnt/backups && test -f /mnt/backups/restic/config");
    nodeReport.checks.nfs_and_repo = { ok: nfs.ok };
    if (!nfs.ok) nodeReport.issues.push("nfs_not_mounted_or_repo_missing");

    // Timer status
    const timer = await ssh(userAtIp, "systemctl is-enabled restic-backup.timer && systemctl is-active restic-backup.timer");
    nodeReport.checks.timer_enabled_active = { ok: timer.ok, out: timer.stdout.trim(), err: timer.stderr.trim() };
    if (!timer.ok) nodeReport.issues.push("timer_not_enabled_or_not_active");

    // Last run summary
    const last = await ssh(
      userAtIp,
      "systemctl show restic-backup.service -p Result -p ExecMainStatus -p ExecMainStartTimestamp -p ExecMainExitTimestamp",
    );
    nodeReport.checks.last_run = { ok: last.ok, out: last.stdout.trim(), err: last.stderr.trim() };

    // Flag a failed last run if systemd says it wasn't successful.
    if (last.ok) {
      const result = (last.stdout.match(/^Result=(.*)$/m)?.[1] ?? "").trim();
      const statusStr = (last.stdout.match(/^ExecMainStatus=(.*)$/m)?.[1] ?? "").trim();
      const startTs = (last.stdout.match(/^ExecMainStartTimestamp=(.*)$/m)?.[1] ?? "").trim();
      const status = Number.parseInt(statusStr || "0", 10);

      if (result && result !== "success") nodeReport.issues.push("last_run_failed");
      if (!Number.isNaN(status) && status !== 0) nodeReport.issues.push("last_run_nonzero_exit");
      if (jobs.length > 0 && (!startTs || startTs === "n/a")) nodeReport.issues.push("no_recorded_last_run");
    }

    // Journal tail
    const journal = await ssh(userAtIp, "journalctl -u restic-backup.service -n 80 --no-pager");
    nodeReport.checks.journal_tail = { ok: journal.ok, lines: (journal.stdout || "").split("\n").filter(Boolean).slice(-80) };
    if (!journal.ok) nodeReport.issues.push("cannot_read_journal");

    // Snapshots (per tag + host)
    if (jobs.length === 0) {
      nodeReport.checks.snapshots = { ok: true, note: "no jobs configured" };
    } else {
      for (const tag of jobs) {
        const cmd = `sudo -n ${RESTIC_BIN} snapshots --repo ${REPO} --password-file ${PASS_FILE} --tag ${tag} --host ${node} --json --latest 1`;
        const r = await ssh(userAtIp, cmd, 120_000);
        if (!r.ok) {
          nodeReport.snapshots[tag] = { ok: false, error: (r.stderr.trim() || r.stdout.trim()) };
          nodeReport.issues.push(`snapshot_query_failed:${tag}`);
          continue;
        }

        let snaps: any[];
        try {
          snaps = JSON.parse(r.stdout);
        } catch {
          nodeReport.snapshots[tag] = { ok: false, error: "invalid_json_from_restic" };
          nodeReport.issues.push(`snapshot_query_failed:${tag}`);
          continue;
        }

        if (!snaps || snaps.length === 0) {
          nodeReport.snapshots[tag] = { ok: false, error: "no_snapshots_for_tag" };
          nodeReport.issues.push(`no_snapshots:${tag}`);
          continue;
        }

        const s0 = snaps[0];
        const t = parseResticTime(s0?.time);
        let ageHours: number | undefined;
        let stale: boolean | undefined;
        if (t) {
          ageHours = (nowUtcMs - t.getTime()) / (1000 * 60 * 60);
          stale = ageHours > STALE_HOURS;
        }

        nodeReport.snapshots[tag] = {
          ok: true,
          id: s0?.short_id ?? s0?.id,
          time: s0?.time,
          age_hours: ageHours,
          stale,
          paths: s0?.paths,
        };

        if (stale) nodeReport.issues.push(`stale_snapshot:${tag}`);
      }
    }

    (report.nodes as any)[node] = nodeReport;
  }

  const issueCount =
    report.nas.issues.length +
    Object.values(report.nodes).reduce((acc: number, n: any) => acc + (n.issues?.length ?? 0), 0);

  report.ok = issueCount === 0;
  report.issue_count = issueCount;

  process.stdout.write(JSON.stringify(report, null, 2) + "\n");
  return report.ok ? 0 : 2;
}

process.exit(await main());

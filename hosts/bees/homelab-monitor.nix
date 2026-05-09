# ── Homelab Infrastructure Monitor ─────────────────────────────────
#
# AI-powered infrastructure monitoring using pi and Prometheus.
# - Every 3 hours: critical check (alerts via ntfy only if issues found)
# - Daily at 8 AM ET: comprehensive health report (always sent)
#
# Data collection (TypeScript, runs via bun):
#   - Prometheus metrics (CPU, memory, disk, network) for NixOS hosts
#   - SSH to NAS and gateway for status (until migrated to NixOS)
#   - Local journalctl/dmesg on bees
#
# AI analysis via: pi -p --no-tools
# Notifications via: ntfy topic "homelab-monitor"

{ config, lib, pkgs, unstable, ... }:

let
  pi-pkg = unstable."pi-coding-agent";
in
{
  # System prompt file for pi analysis
  environment.etc."homelab-monitor/system-prompt.md".source = ./homelab-monitor/system-prompt.md;

  # Install collect.ts at a stable path for on-demand remote use
  environment.etc."homelab-monitor/collect.ts" = {
    source = ./homelab-monitor/collect.ts;
    mode = "0644";
  };

  # bun available system-wide for SSH on-demand invocations
  environment.systemPackages = [ pkgs.bun ];

  # ── 3-hourly critical check ────────────────────────────────────
  systemd.services.homelab-monitor-check = {
    description = "Homelab Monitor — Critical Check";
    path = [ pkgs.bun pkgs.openssh pi-pkg ];
    serviceConfig = {
      Type = "oneshot";
      User = "crussell";
      ExecStart = "${pkgs.bun}/bin/bun ${./homelab-monitor/collect.ts} check";
      TimeoutStartSec = "300";
      Environment = "OPENROUTER_API_KEY=%d/openrouter-api-key";
      LoadCredential = "openrouter-api-key:${config.age.secrets.openrouter-api-key.path}";
    };
  };

  # ── Daily comprehensive report ─────────────────────────────────
  systemd.services.homelab-monitor-daily = {
    description = "Homelab Monitor — Daily Report";
    path = [ pkgs.bun pkgs.openssh pi-pkg ];
    serviceConfig = {
      Type = "oneshot";
      User = "crussell";
      ExecStart = "${pkgs.bun}/bin/bun ${./homelab-monitor/collect.ts} daily";
      TimeoutStartSec = "300";
      Environment = "OPENROUTER_API_KEY=%d/openrouter-api-key";
      LoadCredential = "openrouter-api-key:${config.age.secrets.openrouter-api-key.path}";
    };
  };

  # ── Timer: every 3 hours ───────────────────────────────────────
  systemd.timers.homelab-monitor-check = {
    description = "Homelab critical check every 3 hours";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 00/3:00:00";
      Persistent = true;
      RandomizedDelaySec = "5m";
    };
  };

  # ── Timer: daily at 8 AM ───────────────────────────────────────
  systemd.timers.homelab-monitor-daily = {
    description = "Homelab daily report at 8 AM";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 08:00:00";
      Persistent = true;
      RandomizedDelaySec = "10m";
    };
  };
}

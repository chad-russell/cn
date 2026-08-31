# ── Trades recommendation site on bee ──────────────────────────────
#
# Read-only view over ~/tasty_options/data/portfolio.db (scan_runs +
# recommendations, produced by the deterministic scanner). Terminal-desk
# UI at https://trades.internal.crussell.io — bees Caddy terminates TLS
# (wildcard *.internal.crussell.io) and proxies to bee over Nebula
# (10.10.0.12:8901), same pattern as hermes-serve / hermes-webui.
#
# Two pieces, both declarative:
#   1. trades-site.service (system service) — stdlib HTTP server
#      (tracker/site.py). Credential-free: opens the DB read-only; its
#      ONLY write path is POST /api/scan, which spawns `./run scan`
#      as crussell (rootless podman container does the API work).
#   2. trades-scan.timer/.service (USER unit, crussell) — 10:30 ET
#      weekday scan via the ./run wrapper (needs rootless podman +
#      .env credentials, so it must run as the user, not root).
#
# The DB lives in ~/tasty_options/data (crussell-owned). The system
# service reads it directly (read-only handle) — no podman involved.

{ config, lib, pkgs, ... }:

let
  tastyRoot = "/home/crussell/tasty_options";
in
{
  # ── 1) Site service (system) ─────────────────────────────────────
  systemd.services.trades-site = {
    description = "Trades recommendation site (read-only portfolio.db view)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "simple";
      User = "crussell";
      Group = "users";
      # Nebula-overlay bind — bees Caddy reaches this over Nebula, same
      # door policy as hermes-webui (10.10.0.12). Never LAN/public.
      Environment = [
        "HOST=10.10.0.12"
        "PORT=8901"
      ];
      ExecStart = "${pkgs.python3}/bin/python ${tastyRoot}/tracker/site.py";
      WorkingDirectory = tastyRoot;
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  # ── 2) Daily scan (user unit — needs rootless podman + .env) ─────
  systemd.user.services."trades-scan" = {
    description = "Tastytrade deterministic recommendation scan";
    # Skip cleanly if the checkout moves.
    unitConfig.ConditionPathExists = "${tastyRoot}/run";
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "15min";
      ExecStart = "${pkgs.bash}/bin/bash -lc 'cd ${tastyRoot} && ./run scan --trigger scheduled'";
    };
    path = [ pkgs.bash pkgs.podman pkgs.coreutils ];
  };

  systemd.user.timers."trades-scan" = {
    description = "Weekday 10:30 ET trade-recommendation scan";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Mon..Fri 10:30:00";
      Persistent = true;
    };
  };
}

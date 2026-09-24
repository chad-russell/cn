# ── Kan (kan.bn): open-source Trello alternative ───────────────────
#
# Self-hosted Kan behind the gateway's public Caddy at
# https://trello.crussell.io (basic_auth gated). Runs as podman quadlets
# on bees:
#
#   kan.network          — bridge network (DNS: kan-web ↔ kan-postgres)
#   kan-postgres.service — Postgres 15, named volume kan_postgres_data
#   kan-migrate.service  — one-shot drizzle migrations (quadlet with
#                          Type=oneshot + RemainAfterExit; restart to
#                          re-run migrations after image bumps)
#   kan-web.service      — ghcr.io/kanbn/kan:latest on 127.0.0.1:3300
#
# Secrets in /run/agenix/kan-env (agenix): POSTGRES_PASSWORD,
# POSTGRES_URL, BETTER_AUTH_SECRET, KAN_ADMIN_API_KEY.
# First user to sign up becomes workspace owner → sign-up is disabled
# AFTER the first login works (NEXT_PUBLIC_DISABLE_SIGN_UP=true ships
# pre-set; flip to false in kan.container and redeploy if a re-signup
# is ever needed).
#
# Verify: https://trello.crussell.io (basic auth) → Kan login page.

{ config, lib, pkgs, ... }:

{
  age.secrets.kan-env = {
    file = ../../secrets/kan-env.age;
    mode = "0600";
  };

  environment.etc."containers/systemd/kan.container" = {
    source = ./kan.container;
    mode = "0644";
  };
  environment.etc."containers/systemd/kan-postgres.container" = {
    source = ./kan-postgres.container;
    mode = "0644";
  };
  environment.etc."containers/systemd/kan-migrate.container" = {
    source = ./kan-migrate.container;
    mode = "0644";
  };
  environment.etc."containers/systemd/kan.network" = {
    source = ./kan.network;
    mode = "0644";
  };

  system.activationScripts.kan-dirs = lib.stringAfter [ "users" ] ''
    mkdir -p /var/lib/kan
    chmod 755 /var/lib/kan
  '';

  # Nightly logical dump of Kan's Postgres. Restic covers the live PG
  # data dir only via the container volume (a running-Postgres copy can
  # restore torn); a pg_dump is independently restorable — the same
  # discipline as immich-db-dump. Dumps land in /var/lib/kan/backups
  # (already a restic path via /var/lib/kan), newest 14 kept.
  systemd.services.kan-db-dump = {
    description = "Kan Postgres logical dump";
    path = with pkgs; [ podman gzip coreutils ];
    requires = [ "kan-postgres.service" ];
    after = [ "kan-postgres.service" ];
    onFailure = [ "ntfy-failure@kan-db-dump.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    script = ''
      set -euo pipefail
      mkdir -p /var/lib/kan/backups
      ts="$(date -u +%Y%m%dT%H%M%SZ)"
      out="/var/lib/kan/backups/kan-pgdump-$ts.sql.gz"
      podman exec kan-postgres pg_dump -U kan kan_db | gzip -c > "$out.tmp"
      mv "$out.tmp" "$out"
      chmod 600 "$out"
      # Keep the newest 14 dumps; drop anything older.
      ls -1t /var/lib/kan/backups/kan-pgdump-*.sql.gz 2>/dev/null | tail -n +15 | xargs -r rm -f --
    '';
  };

  systemd.timers.kan-db-dump = {
    description = "Nightly Kan Postgres dump";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # 03:07 — after the 03:01 immich dump, before the 05:00 restic window.
      OnCalendar = "*-*-* 03:07:00";
      Persistent = true;
      RandomizedDelaySec = "10min";
    };
  };
}

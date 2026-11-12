# ── Kaneo (kaneo.app): project management ──────────────────────────
#
# Self-hosted Kaneo behind the gateway's public Caddy at
# https://kaneo.crussell.io (no basic_auth — Kaneo's own login is the
# gate; registration stays open for first boot only, then the owner
# closes it via the admin UI or a follow-up env change). Runs as podman
# quadlets on bees:
#
#   kaneo.network          — bridge network (DNS: kaneo ↔ kaneo-postgres)
#   kaneo-postgres.service — Postgres 16-alpine, named volume
#                            kaneo_postgres_data, Notify=healthy
#   kaneo.service          — ghcr.io/usekaneo/kaneo:2.49.0 on :5173
#                            (all-interfaces PublishPort — house pattern
#                            for the gateway's Nebula proxy)
#
# The app runs its own DB migrations on start (no separate migrate unit).
# Secrets in /run/agenix/kaneo-env (agenix): POSTGRES_PASSWORD,
# AUTH_SECRET. Runbook: docs/kaneo/README.md.
#
# Verify: https://kaneo.crussell.io → Kaneo sign-in page.

{ config, lib, pkgs, ... }:

{
  age.secrets.kaneo-env = {
    file = ../../secrets/kaneo-env.age;
    mode = "0600";
  };

  environment.etc."containers/systemd/kaneo.container" = {
    source = ./kaneo.container;
    mode = "0644";
  };
  environment.etc."containers/systemd/kaneo-postgres.container" = {
    source = ./kaneo-postgres.container;
    mode = "0644";
  };
  environment.etc."containers/systemd/kaneo.network" = {
    source = ./kaneo.network;
    mode = "0644";
  };

  # Nightly logical dump of the kaneo DB (podman exec into the postgres
  # container; gzip'd into /var/lib/kaneo/db-dumps, newest 14 kept).
  systemd.services.kaneo-db-dump = {
    description = "Kaneo Postgres logical dump";
    path = [ pkgs.podman pkgs.gzip pkgs.coreutils ];
    after = [ "kaneo-postgres.service" ];
    onFailure = [ "ntfy-failure@kaneo-db-dump.service" ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };

    script = ''
      set -euo pipefail

      ts="$(date -u +%Y%m%dT%H%M%SZ)"
      out="/var/lib/kaneo/db-dumps/kaneo-pgdump-$ts.sql.gz"
      ${pkgs.podman}/bin/podman exec kaneo-postgres pg_dump -U kaneo kaneo \
        | ${pkgs.gzip}/bin/gzip -c > "$out.tmp"
      mv "$out.tmp" "$out"
      chmod 600 "$out"

      # Keep the newest 14 dumps; drop anything older.
      ls -1t /var/lib/kaneo/db-dumps/kaneo-pgdump-*.sql.gz 2>/dev/null \
        | tail -n +15 | xargs -r rm -f --

      echo "wrote $out"
    '';
  };

  systemd.timers.kaneo-db-dump = {
    description = "Daily Kaneo DB dump";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  # Output-layer monitoring: the dump must stay fresh.
  homelab.freshnessChecks.kaneo-db = {
    description = "Kaneo Postgres dump";
    path = "/var/lib/kaneo/db-dumps";
    glob = "kaneo-pgdump-*.sql.gz";
    maxAgeHours = 36;
  };

  system.activationScripts.kaneo-dirs = lib.stringAfter [ "users" ] ''
    mkdir -p /var/lib/kaneo/db-dumps
    chmod 755 /var/lib/kaneo
  '';
}

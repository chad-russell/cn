# ── Immich DB dump (NixOS-managed) ──────────────────────────────────
#
# Daily logical dump of the Immich Postgres DB to the NFS photos share, so
# restic scoops it up in the nightly backup. Replaces Immich's opaque in-app
# backup feature, which silently stopped producing dumps for ~5 weeks with
# no signal (the restic job kept "succeeding" on a stale file).
#
# This makes the dump a monitored systemd job (onFailure → ntfy) and lets
# the freshness-immich-db check validate it's staying current.
#
# → Once this is live, disable Immich's built-in backup in the admin UI
#   (Administration → Backup) so there's a single source of dumps.

{ config, lib, pkgs, ... }:

let
  dumpDir = "/mnt/photos/backups";
  pg = config.services.postgresql.package;
in
{
  systemd.services.immich-db-dump = {
    description = "Immich Postgres logical dump";
    path = [
      pkgs.util-linux # runuser
      pkgs.gzip
      pkgs.coreutils
    ];
    requires = [ "postgresql.service" "mnt-photos.automount" ];
    after = [ "postgresql.service" "mnt-photos.automount" ];
    onFailure = [ "ntfy-failure@immich-db-dump.service" ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };

    script = ''
      set -euo pipefail
      # Trigger the automount and fail early if the NFS share is unreachable.
      ls -d ${dumpDir} >/dev/null

      ts="$(date -u +%Y%m%dT%H%M%SZ)"
      out="${dumpDir}/immich-pgdump-$ts.sql.gz"
      runuser -u postgres -- ${pg}/bin/pg_dump immich | ${pkgs.gzip}/bin/gzip -c > "$out.tmp"
      mv "$out.tmp" "$out"
      chmod 600 "$out"

      # Keep the newest 14 dumps; drop anything older.
      ls -1t ${dumpDir}/immich-pgdump-*.sql.gz 2>/dev/null | tail -n +15 | xargs -r rm -f --

      echo "wrote $out"
    '';
  };

  systemd.timers.immich-db-dump = {
    description = "Daily Immich DB dump";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  # Output-layer monitoring: the dump must stay fresh.
  homelab.freshnessChecks.immich-db = {
    description = "Immich Postgres dump";
    path = dumpDir;
    glob = "immich-pgdump-*.sql.gz";
    maxAgeHours = 36;
  };
}

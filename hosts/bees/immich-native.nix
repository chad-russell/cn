# ── Immich: native host services (quadlet era) ──────────────────────
#
# Everything immich that stays NATIVE on bees now that the NixOS immich
# module is gone (immich-loop PLAN D2): Postgres, redis-immich, the
# nightly DB dump, and the dump freshness check. The immich server + ML
# containers are quadlets wired by the cutover commit in
# hosts/bees/immich-quadlet.nix (not imported before cutover — see
# docs/immich-loop/RUNBOOK-cutover.md §3).
#
# The dump + freshness sections are hosts/bees/immich-backup.nix carried
# over VERBATIM by the post-soak cleanup (task D2); they never depended
# on the module. The postgres/redis blocks re-declare what services.immich
# used to own, runbook-exact (RUNBOOK §3c): ensure* only create, never
# drop, so they are a no-op against the existing DB; extensions already
# installed persist (verify post-cutover per runbook §1.5).
#
# Ids: immich = 991:993 and nas-photos gid = 1000 — pinned below (FACTS.md);
# redis-immich = 992 stays module-held (see the pin block comment).
#
# → Once this is live, disable Immich's built-in backup in the admin UI
#   (Administration → Backup) so there's a single source of dumps.

{ config, lib, pkgs, ... }:

let
  dumpDir = "/mnt/photos/backups";
  pg = config.services.postgresql.package;
in {
  # ── Id reservations (FACTS.md: immich 991:993, nas-photos gid 1000) ──
  # The nixpkgs immich module declared the immich user/group with
  # auto-allocated ids (mutableUsers persisted them as 991/993 on bees).
  # With the module gone, pin them so nothing can re-allocate the ids:
  # the quadlets hardcode User=991:993 (PG peer auth and NFS ownership
  # are numeric — /mnt/photos root is immich:immich 700) and A2's NFS
  # uid/gid mapping references gid 1000. Values match the live
  # /etc/passwd + /etc/group entries, so the first switch is a no-op.
  # (redis-immich needs no pin: services.redis below keeps its group
  # declared, so its mutableUsers gid reservation persists.)
  users.users.immich = {
    uid = 991;
    isSystemUser = true;
    group = "immich";
  };
  users.groups.immich.gid = 993;
  users.groups.nas-photos.gid = 1000;

  # ── Survivors the immich module used to own (RUNBOOK §3c) ──────────
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17; # 26.05 default; pin explicitly
    ensureDatabases = [ "immich" ];
    ensureUsers = [{
      name = "immich";
      ensureDBOwnership = true;
      ensureClauses.login = true;
    }];
    extensions = ps: [ ps.pgvector ps.vectorchord ];
    settings = {
      shared_preload_libraries = [ "vchord.so" ];
      search_path = ''"$user", public, vectors'';
    };
    authentication = ''
      # same policy the module shipped (FACTS: socket=peer, loopback=md5)
      local all all peer
      host  all all 127.0.0.1/32 md5
      host  all all ::1/128      md5
    '';
  };

  services.redis.servers.immich = {
    enable = true;
    logLevel = "warning";
    # unix socket default (/run/redis-immich/redis.sock); the quadlets mount
    # /run/redis-immich and the server container auths via REDIS_SOCKET.
  };

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

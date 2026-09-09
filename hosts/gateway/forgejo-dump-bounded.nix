# ── gateway: nightly Forgejo dump into a bounded pull directory ────
#
# The NixOS forgejo module's built-in `dump.enable` timer has no retention
# control (dumps accumulate in stateDir/dump forever on a 75G VPS) and fires
# at a fixed 04:31. This replaces it with the same `forgejo dump` invocation
# (user, workdir, env — mirrored from the module's unit) writing into
# /var/lib/forgejo/dump-temp/<unix-ts>.zip and keeping only the newest 3.
#
# bees pulls dump-temp/ nightly (hosts/bees/forgejo-backup-pull.nix) and
# covers it in restic; gateway stays secret-free — it only ever creates the
# dump, S3/restic credentials never touch the VPS.

{ config, lib, pkgs, ... }:

let dumpDir = "/var/lib/forgejo/dump-temp";
in {
  # The built-in daily dump timer is replaced by the custom unit below —
  # running both would double the nightly dump (zip + repos re-zip) on the
  # small VPS and grow stateDir/dump unbounded.
  services.forgejo.dump.enable = false;

  systemd.services.forgejo-dump-bounded = {
    description = "Forgejo nightly dump into ${dumpDir} (retain 3)";
    after = [ "forgejo.service" ];
    wants = [ "forgejo.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "forgejo";
      Group = "forgejo";
      # forgejo dump reads app.ini + SQLite inside the live state dir.
      WorkingDirectory = "/var/lib/forgejo";
    };
    environment = {
      FORGEJO_WORK_DIR = "/var/lib/forgejo";
      FORGEJO_CUSTOM = "/var/lib/forgejo/custom";
      HOME = "/var/lib/forgejo";
    };
    path = [ pkgs.coreutils pkgs.findutils pkgs.gnused ];
    script = ''
      set -euo pipefail
      mkdir -p ${dumpDir}
      cd /var/lib/forgejo

      ts=$(date +%s)
      out=${dumpDir}/forgejo-dump-$ts.zip

      # Same invocation the module's own dump unit used: full backup
      # (repos + db + config + lfs) as a single zip. Forgejo 15's flag is
      # --file/-f (there is no --output).
      ${config.services.forgejo.package}/bin/forgejo dump --type zip --file "$out"

      # Atomic size sanity gate: a dump must be meaningfully bigger than the
      # SQLite journal (repos alone are ~9 MiB even before the DB) — guards
      # against an empty/partial zip silently becoming "the newest dump".
      minBytes=1000000   # 1 MB
      size=$(stat -c%s "$out")
      if [ "$size" -lt "$minBytes" ]; then
        echo "dump suspiciously small: $out is ''${size} bytes (< $minBytes) — removing" >&2
        rm -f "$out"
        exit 1
      fi

      # Retain the newest 3 dumps only.
      ls -t ${dumpDir}/forgejo-dump-*.zip | tail -n +4 | xargs -r rm -f
      echo "kept:"
      ls -t ${dumpDir}/forgejo-dump-*.zip
    '';
    onFailure = [ "ntfy-failure@forgejo-dump-bounded.service" ];
  };

  systemd.timers.forgejo-dump-bounded = {
    description = "Nightly Forgejo dump (retain 3)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 03:30:00";
      Persistent = true;
    };
  };
}

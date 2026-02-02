{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.resticBackup;

  resticBackupBin = pkgs.writeShellScriptBin "restic-backup" ''
    set -euo pipefail

    CONFIG="${cfg.configFile}"

    export RESTIC_PASSWORD_FILE="${cfg.passwordFile}"
    export RESTIC_REPOSITORY="${cfg.repository}"

    echo "[$(${pkgs.coreutils}/bin/date +'%Y-%m-%d %H:%M:%S')] restic-backup: start"

    if ! ${pkgs.util-linux}/bin/mountpoint -q /mnt/backups; then
      echo "[$(${pkgs.coreutils}/bin/date +'%Y-%m-%d %H:%M:%S')] restic-backup: ERROR: /mnt/backups not mounted" >&2
      exit 1
    fi

    # restic stores repo metadata in a *file* named "config".
    if [ ! -f "$RESTIC_REPOSITORY/config" ]; then
      echo "[$(${pkgs.coreutils}/bin/date +'%Y-%m-%d %H:%M:%S')] restic-backup: init repo" 
      ${pkgs.restic}/bin/restic init
    fi

    ${pkgs.jq}/bin/jq -c '.jobs[]' "$CONFIG" | while read -r job; do
      name=$(printf '%s' "$job" | ${pkgs.jq}/bin/jq -r '.name')
      type=$(printf '%s' "$job" | ${pkgs.jq}/bin/jq -r '.type // "volume"')

      echo "[$(${pkgs.coreutils}/bin/date +'%Y-%m-%d %H:%M:%S')] restic-backup: backing up $name ($type)"

      # Print each target on its own line; read in a loop to preserve paths with spaces.
      printf '%s' "$job" | ${pkgs.jq}/bin/jq -r '.targets[]? // empty' | while IFS= read -r target; do
        [ -z "$target" ] && continue

        if [ "$type" = "volume" ]; then
          mountpoint=$(${pkgs.docker}/bin/docker volume inspect -f '{{.Mountpoint}}' "$target" 2>/dev/null || true)
          if [ -z "$mountpoint" ]; then
            echo "[$(${pkgs.coreutils}/bin/date +'%Y-%m-%d %H:%M:%S')] restic-backup: ERROR: volume not found: $target" >&2
            exit 1
          fi
          ${pkgs.restic}/bin/restic backup "$mountpoint" --tag "$name"
        else
          if [ ! -e "$target" ]; then
            echo "[$(${pkgs.coreutils}/bin/date +'%Y-%m-%d %H:%M:%S')] restic-backup: WARN: path missing, skipping: $target" >&2
            continue
          fi
          ${pkgs.restic}/bin/restic backup "$target" --tag "$name"
        fi
      done
    done

    echo "[$(${pkgs.coreutils}/bin/date +'%Y-%m-%d %H:%M:%S')] restic-backup: pruning"
    ${pkgs.restic}/bin/restic forget \
      --keep-hourly 24 \
      --keep-daily 7 \
      --keep-weekly 4 \
      --keep-monthly 3 \
      --keep-yearly 1 \
      --prune

    echo "[$(${pkgs.coreutils}/bin/date +'%Y-%m-%d %H:%M:%S')] restic-backup: done"
  '';
in {
  options.services.resticBackup = {
    enable = mkEnableOption "Restic-based backup system";

    configFile = mkOption {
      type = types.path;
      default = pkgs.writeText "restic-backup.json" (builtins.toJSON { jobs = []; });
      description = "Path to restic backup configuration JSON (ideally from the flake, so it lives in the Nix store).";
    };

    passwordFile = mkOption {
      type = types.path;
      default = "/etc/restic-password";
      description = "Path to restic repository password file.";
    };

    repository = mkOption {
      type = types.str;
      default = "/mnt/backups/restic";
      description = "Path to restic repository.";
    };

    schedule = mkOption {
      type = types.str;
      default = "03:00:00";
      description = "Systemd OnCalendar value for when to run backups.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ resticBackupBin ];

    systemd.services.restic-backup = {
      description = "Run Restic backups";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${resticBackupBin}/bin/restic-backup";
      };
    };

    systemd.timers.restic-backup = {
      description = "Timer for Restic backups";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        Unit = "restic-backup.service";
      };
    };
  };
}

# ── Shared Restic Backup Configuration ──────────────────────────────
#
# Provides a `config.services.homelab-backup` option that each host
# uses to declare what to back up.  Creates two restic repos per host:
#
#   1. NAS  →  /mnt/backups/<hostname>        (local copy)
#   2. S3   →  s3:crussell-restic-backups/<hostname>   (us-east-2)
#
# Both run daily via systemd timers.  On failure, a notification is
# pushed to ntfy.
#
# Usage (per-host):
#
#   services.homelab-backup = {
#     enable = true;
#     paths = [ "/var/lib/important" ];
#     exclude = [ "*.tmp" ];
#   };

{ config, lib, pkgs, ... }:

let
  cfg = config.services.homelab-backup;
  hostname = config.networking.hostName;

  # ── ntfy notification helper ────────────────────────────────────
  ntfyUrl = "https://ntfy.internal.crussell.io/homelab-backups";
  ntfyScript = pkgs.writeShellScript "restic-ntfy-notify" ''
    STATUS=$1
    TARGET=$2
    shift 2
    MSG="$*"

    ${pkgs.curl}/bin/curl -s \
      -H "Title: Backup $STATUS on ${hostname}" \
      -H "Tags: $([ "$STATUS" = "FAILED" ] && echo rotating_light || echo white_check_mark)" \
      -H "Priority: $([ "$STATUS" = "FAILED" ] && echo high || echo default)" \
      -d "$TARGET on ${hostname}: $MSG" \
      "${ntfyUrl}" > /dev/null 2>&1 || true
  '';

  # ── Shared restic options ───────────────────────────────────────
  resticPkg = pkgs.restic;

  makeBackupJob =
    { name, repo, passwordFile, environmentFile, retention }:
    let
      jobName = "homelab-${name}";
    in
    {
      "${jobName}" = {
        package = resticPkg;
        repository = repo;
        inherit passwordFile;
        environmentFile = lib.mkIf (environmentFile != null) environmentFile;

        paths = cfg.paths;
        exclude = cfg.exclude;

        initialize = true;

        pruneOpts = retention;

        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
          RandomizedDelaySec = "1h";
        };

        extraBackupArgs = [
          "--cleanup-cache"
          "--one-file-system"
        ];

        backupPrepareCommand = ''
          echo "Starting ${name} backup for ${hostname} at $(date)"
        '';

        backupCleanupCommand = ''
          echo "Finished ${name} backup for ${hostname} at $(date)"
        '';
      };
    };

  # ── Weekly integrity check job ─────────────────────────────────
  # restic strongly recommends periodic `check` to detect repo/index
  # corruption before you need to restore.  --read-data-subset=5% reads
  # a random 5% of packs each run (≈20 weeks to cycle the whole repo on
  # a weekly timer), keeping S3 GET costs negligible.
  makeCheckJob =
    { name, repo, passwordFile, environmentFile ? null, requires ? [ ] }:
    let
      jobName = "homelab-${name}";
    in
    {
      "restic-checks-${jobName}" = {
        description = "Restic weekly integrity check (${name})";
        path = [ resticPkg ];
        serviceConfig = {
          Type = "oneshot";
        } // (lib.optionalAttrs (environmentFile != null) {
          EnvironmentFile = environmentFile;
        });
        environment = {
          RESTIC_REPOSITORY = repo;
          RESTIC_PASSWORD_FILE = passwordFile;
        };
        inherit requires;
        after = requires;
        onFailure = [ "restic-ntfy-failure@${name}-check.service" ];
        script = ''
          echo "Starting restic check (${name}) on ${hostname} at $(date)"
          ${resticPkg}/bin/restic check --read-data-subset=5%
        '';
      };
    };

in
{
  options.services.homelab-backup = {
    enable = lib.mkEnableOption "homelab restic backup (NAS + S3)";

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Paths to back up.";
    };

    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Patterns to exclude from backups.";
    };

    s3Bucket = lib.mkOption {
      type = lib.types.str;
      default = "crussell-restic-backups";
      description = "S3 bucket name for offsite backups.";
    };

    s3Region = lib.mkOption {
      type = lib.types.str;
      default = "us-east-2";
      description = "AWS region for the S3 bucket.";
    };

    nasMountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/backups";
      description = "Local mount point for NAS backup target.";
    };

    ntfyUrl = lib.mkOption {
      type = lib.types.str;
      default = ntfyUrl;
      description = "ntfy topic URL for backup notifications.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.paths != [ ];
        message = "homelab-backup: at least one path must be specified";
      }
    ];

    # ── Restic backup jobs ────────────────────────────────────────
    services.restic.backups =
      let
        nasRetension = [
          "--keep-daily 30"
        ];
        s3Retention = [
          "--keep-daily 30"
          "--keep-monthly 12"
        ];
      in
      (makeBackupJob {
        name = "nas";
        repo = "${cfg.nasMountPoint}/${hostname}";
        passwordFile = config.age.secrets.restic-password.path;
        environmentFile = null;
        retention = nasRetension;
      }) //
      (makeBackupJob {
        name = "s3";
        repo = "s3:https://s3.${cfg.s3Region}.amazonaws.com/${cfg.s3Bucket}/${hostname}";
        passwordFile = config.age.secrets.restic-password.path;
        environmentFile = config.age.secrets.restic-s3-credentials.path;
        retention = s3Retention;
      });

    # ── Decrypt secrets via agenix ────────────────────────────────
    age.secrets = {
      restic-password = {
        file = ../secrets/restic-password-${hostname}.age;
        mode = "0400";
        owner = "root";
        group = "root";
      };
      restic-s3-credentials = {
        file = ../secrets/restic-s3-credentials.age;
        mode = "0400";
        owner = "root";
        group = "root";
      };
    };

    # ── ntfy notifications on failure ─────────────────────────────
    systemd.services =
      let
        nasRequires = [ "mnt-backups.automount" ];
        nasRepo = "${cfg.nasMountPoint}/${hostname}";
        s3Repo = "s3:https://s3.${cfg.s3Region}.amazonaws.com/${cfg.s3Bucket}/${hostname}";
        resticPwd = config.age.secrets.restic-password.path;
        s3Creds = config.age.secrets.restic-s3-credentials.path;
      in
      {
        "restic-backups-homelab-nas" = {
          requires = nasRequires;
          after = nasRequires;
          onFailure = [ "restic-ntfy-failure@nas.service" ];
        };
        "restic-backups-homelab-s3" = {
          onFailure = [ "restic-ntfy-failure@s3.service" ];
        };
        "restic-ntfy-failure@" = {
          description = "Send ntfy notification on restic backup failure";
          serviceConfig.Type = "oneshot";
          script = ''
            TARGET=$1
            ${ntfyScript} "FAILED" "$TARGET" "Check journalctl for details"
          '';
          scriptArgs = "%i";
        };
      }
      // (makeCheckJob {
        name = "nas";
        repo = nasRepo;
        passwordFile = resticPwd;
        requires = nasRequires;
      })
      // (makeCheckJob {
        name = "s3";
        repo = s3Repo;
        passwordFile = resticPwd;
        environmentFile = s3Creds;
      });

    # ── Weekly check timers ───────────────────────────────────────
    systemd.timers = {
      "restic-checks-homelab-nas" = {
        description = "Weekly restic integrity check (NAS)";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "weekly";
          Persistent = true;
          RandomizedDelaySec = "2h";
        };
      };
      "restic-checks-homelab-s3" = {
        description = "Weekly restic integrity check (S3)";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "weekly";
          Persistent = true;
          RandomizedDelaySec = "2h";
        };
      };
    };
  };
}

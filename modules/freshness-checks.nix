# ── Freshness checks + ntfy alerting ────────────────────────────────
#
# Catches the failure mode that "did the job exit 0?" alerts miss: an
# artifact that silently stopped being refreshed (e.g. an app's in-built
# backup feature quietly turning off, or a timer getting disabled). The
# restic backup kept "succeeding" every night while backing up a stale
# Immich DB dump for ~5 weeks — because nothing checked the artifact's age.
#
# Two complementary layers:
#   - process: any service can `onFailure = [ "ntfy-failure@<name>.service" ]`
#   - output:   homelab.freshnessChecks.<name> watches the produced artifact
#
# Each freshness check is one of:
#   - file mode:    newest file matching `glob` under `path` must be < maxAgeHours old
#   - command mode: `checkCommand` exits 0 if fresh, non-zero if stale
# Stale (or a crashed job) → ntfy.

{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.freshnessChecks;
  hostname = config.networking.hostName;

  # Build the per-check script. Generating one script per check (rather than
  # a shared helper + env vars) avoids systemd Environment= newline issues
  # and lets `checkCommand` be arbitrary multi-line bash.
  mkCheckScript =
    name: c:
    pkgs.writeShellScript "freshness-${name}" ''
      set -o pipefail
      STATUS=OK
      MSG=""
      ${
        if c.checkCommand != null then
          ''
            # command mode: exit 0 = fresh, non-zero = stale
            if MSG=$(${c.checkCommand} 2>&1); then :; else STATUS=STALE; fi
          ''
        else
          ''
            # file mode: age of newest matching file
            newest="$(find '${toString c.path}' -name '${c.glob}' -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1)"
            if [ -z "$newest" ]; then
              MSG="no file matching '${c.glob}' in ${toString c.path}"
              STATUS=STALE
            else
              ts="''${newest%% *}"
              file="''${newest#* }"
              now=$(date +%s)
              ageh=$(( (now - ''${ts%.*}) / 3600 ))
              MSG="newest is ''${ageh}h old: $file"
              [ "''${ageh}" -lt ${toString c.maxAgeHours} ] || STATUS=STALE
            fi
          ''
      }
      echo "${c.description}: $STATUS — $MSG"
      if [ "$STATUS" != "OK" ]; then
        ${pkgs.curl}/bin/curl -fsS \
          -H "Title: $STATUS — ${name} on ${hostname}" \
          -H "Tags: rotating_light" -H "Priority: high" \
          -d "${c.description}: $MSG" \
          "${c.ntfyUrl}" >/dev/null 2>&1 || true
        exit 1
      fi
    '';
in
{
  options.homelab = {
    ntfyUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://ntfy.internal.crussell.io/homelab-backups";
      description = "Default ntfy topic for homelab alerts.";
    };

    freshnessChecks = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          description = lib.mkOption {
            type = lib.types.str;
            description = "Human label used in the ntfy message.";
          };
          # file mode
          path = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Directory to search for the artifact (file mode).";
          };
          glob = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Filename pattern, find -name (file mode).";
          };
          maxAgeHours = lib.mkOption {
            type = lib.types.ints.positive;
            default = 36;
            description = "Max acceptable age of the newest matching file (file mode).";
          };
          # command mode
          checkCommand = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              Custom check: exit 0 = fresh, non-zero = stale; stdout is used
              as the message (command mode). NOTE: escape bash `''${var}` in
              your Nix string.'';
          };
          environmentFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Env file for the check command (command mode).";
          };
          extraPath = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Extra packages on PATH for the check command (command mode).";
          };
          # common
          onCalendar = lib.mkOption {
            type = lib.types.str;
            default = "daily";
            description = "systemd OnCalendar for the check.";
          };
          ntfyUrl = lib.mkOption {
            type = lib.types.str;
            default = config.homelab.ntfyUrl;
            description = "Override the ntfy topic for this check.";
          };
        };
      });
      default = { };
      description = "Artifact freshness checks — alert via ntfy if stale.";
    };
  };

  config = {
    assertions = [
      {
        assertion =
          lib.all
            (c: (c.path != null && c.glob != null) != (c.checkCommand != null))
            (builtins.attrValues cfg);
        message = "freshnessChecks: each check must set EITHER {path,glob} (file mode) OR checkCommand (command mode) — not both, not neither.";
      }
    ];

    # ── Reusable failure notifier ──────────────────────────────────
    # Any service can do:  onFailure = [ "ntfy-failure@<name>.service" ];
    systemd.services."ntfy-failure@" = {
      description = "ntfy alert on service failure (%i)";
      serviceConfig.Type = "oneshot";
      scriptArgs = "%i";
      script = ''
        ${pkgs.curl}/bin/curl -fsS \
          -H "Title: FAILED — $1 on ${hostname}" \
          -H "Tags: rotating_light" -H "Priority: high" \
          -d "Service '$1' failed on ${hostname}. Inspect: journalctl -u $1" \
          "${config.homelab.ntfyUrl}" >/dev/null 2>&1 || true
      '';
    };

    # ── Freshness check services + timers ──────────────────────────
    systemd.services = lib.mapAttrs' (name: c: lib.nameValuePair "freshness-${name}" {
      description = "Freshness check: ${c.description}";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${mkCheckScript name c}";
      } // (lib.optionalAttrs (c.environmentFile != null) {
        EnvironmentFile = c.environmentFile;
      });
      path = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.curl
      ] ++ c.extraPath;
    }) cfg;

    systemd.timers = lib.mapAttrs' (name: c: lib.nameValuePair "freshness-${name}" {
      description = "Freshness check: ${c.description}";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = c.onCalendar;
        Persistent = true;
        RandomizedDelaySec = "30m";
      };
    }) cfg;
  };
}

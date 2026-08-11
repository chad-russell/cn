# ── Beszel Agent Module ─────────────────────────────────────────────
#
# Shared Beszel monitoring agent for NixOS hosts. Each agent connects
# OUT to the hub (on bees) over the Nebula overlay via WebSocket, using a
# universal token, so NO inbound port is required on any host. The agent
# binary ships in the nixpkgs `beszel` package alongside the hub binary.
#
# Usage in a host config:
#
#   imports = [ ../../modules/beszel-agent.nix ];
#   # enable defaults to true; optionally report extra disks:
#   services.beszel-agent.extraFilesystems = [ "/pool" ];
#
# The hub's public KEY + the universal TOKEN live in
# secrets/beszel-agent-env.age (declared below, shared by all hosts).
# Create that secret via agenix after first booting the hub — see
# hosts/bees/beszel.nix.

{ config, lib, pkgs, ... }:

let cfg = config.services.beszel-agent;
in {
  options.services.beszel-agent = {
    enable = lib.mkEnableOption "Beszel monitoring agent";

    hubUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://beszel.internal.crussell.io";
      description = "URL of the Beszel hub the agent connects to.";
    };

    extraFilesystems = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "/pool" "/mnt/media" ];
      description = ''
        Extra mount points/devices to report disk usage for, in addition
        to the root filesystem. Passed to the agent as EXTRA_FILESYSTEMS.
      '';
    };

    extraEnv = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Additional environment variables for beszel-agent.";
    };
  };

  config = lib.mkMerge [
    # Every host that imports this module gets the agent by default.
    { services.beszel-agent.enable = lib.mkDefault true; }

    (lib.mkIf cfg.enable {
      users.users.beszel-agent = {
        isSystemUser = true;
        group = "beszel-agent";
        home = "/var/lib/beszel-agent";
        createHome = false;
      };
      users.groups.beszel-agent = { };

      # Hub public KEY + universal TOKEN — shared by every agent. Owned by
      # the beszel-agent user so the (non-root) service can read it.
      age.secrets.beszel-agent-env = {
        file = ../secrets/beszel-agent-env.age;
        owner = "beszel-agent";
        group = "beszel-agent";
      };

      systemd.services.beszel-agent = {
        description = "Beszel monitoring agent";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        environment = {
          HUB_URL = cfg.hubUrl;
          # WebSocket push only — disable the inbound SSH listener so no
          # port needs to be opened on the host.
          DISABLE_SSH = "true";
        } // (lib.optionalAttrs (cfg.extraFilesystems != [ ]) {
          EXTRA_FILESYSTEMS = lib.concatStringsSep "," cfg.extraFilesystems;
        }) // cfg.extraEnv;

        serviceConfig = {
          ExecStart = "${pkgs.beszel}/bin/beszel-agent";
          # /run/agenix/beszel-agent-env provides KEY= and TOKEN=
          EnvironmentFile = config.age.secrets.beszel-agent-env.path;
          User = "beszel-agent";
          Group = "beszel-agent";
          StateDirectory = "beszel-agent";
          Restart = "on-failure";
          RestartSec = 5;

          # Hardening. Host stats (CPU/mem/net/disk/temp) are read from the
          # world-readable /proc and /sys, so a strict sandbox is fine; the
          # StateDirectory (/var/lib/beszel-agent) stays writable.
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          ProtectClock = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          LockPersonality = true;
          RestrictSUIDSGID = true;
          KeyringMode = "private";
        };
      };
    })
  ];
}

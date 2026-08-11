# ── OpenCode AI Coding Agent ──────────────────────────────────────────
#
# Installs the opencode CLI (TUI + web) and a system-level systemd service
# for the web interface. Imported by bee + bees.
#
# Importing this module defaults opencode (and its web service) ON; set
# `services.opencode.enable = false;` to opt out on a host.
#
# CLI:  just type `opencode` in a terminal
# Web:  http://<host>:4096  (auto-started at boot)
#
# OPENROUTER_API_KEY is supplied to the web service via the agenix secret
# secrets/openrouter-api-key.age (env file).

{ config, lib, pkgs, unstable, ... }:

let cfg = config.services.opencode;
in {
  options.services.opencode = {
    enable = lib.mkEnableOption "opencode AI coding agent";

    web = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description =
          "Enable a system-level systemd service for `opencode web`";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 4096;
        description = "Port for the opencode web interface";
      };

      hostname = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0";
        description = "Hostname / bind address for the web interface";
      };

      directory = lib.mkOption {
        type = lib.types.str;
        default = "/home/crussell";
        description = "Working directory (project root) for opencode";
      };
    };
  };

  config = lib.mkMerge [
    # Default opencode + web ON for every host that imports this module.
    { services.opencode.enable = lib.mkDefault true; }

    (lib.mkIf cfg.enable {
      # OPENROUTER_API_KEY for openrouter models.
      # ZHIPU_API_KEY for the zhipuai-coding-plan provider (Zhipu AI / Z.AI coding plan).
      age.secrets.openrouter-api-key.file = ../secrets/openrouter-api-key.age;
      age.secrets.zai-api-key.file = ../secrets/zai-api-key.age;

      # ── Package ────────────────────────────────────────────────────
      environment.systemPackages = [ unstable.opencode ];

      # ── Web interface systemd service ──────────────────────────────
      systemd.services.opencode-web = lib.mkIf cfg.web.enable {
        description = "OpenCode Web Interface";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "simple";
          User = "crussell";
          Group = "users";
          WorkingDirectory = cfg.web.directory;
          ExecStart = "${unstable.opencode}/bin/opencode web --port ${
              toString cfg.web.port
            } --hostname ${cfg.web.hostname}";
          # Provides OPENROUTER_API_KEY (openrouter) + ZHIPU_API_KEY (zhipuai-coding-plan).
          EnvironmentFile = [
            config.age.secrets.openrouter-api-key.path
            config.age.secrets.zai-api-key.path
          ];
          Restart = "always";
          RestartSec = "5";
          StartLimitIntervalSec = "60";
          StartLimitBurst = "5";
        };
      };
    })
  ];
}

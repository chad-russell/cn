# ── OpenCode AI Coding Agent ──────────────────────────────────────────
#
# Installs the opencode CLI (TUI + web) and optionally provides a
# system-level systemd service for the web interface.
#
# Usage (in a host configuration.nix):
#   services.opencode.enable = true;
#   services.opencode.web.enable = true;   # optional web service
#
# CLI:  just type `opencode` in a terminal
# Web:  systemctl start opencode-web
#       then open http://localhost:4096

{ config, lib, pkgs, unstable, ... }:

let
  cfg = config.services.opencode;
in
{
  options.services.opencode = {
    enable = lib.mkEnableOption "opencode AI coding agent";

    web = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable a system-level systemd service for `opencode web`";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 4096;
        description = "Port for the opencode web interface";
      };

      hostname = lib.mkOption {
        type = lib.types.str;
        default = "localhost";
        description = "Hostname / bind address for the web interface";
      };

      directory = lib.mkOption {
        type = lib.types.str;
        default = "/home/crussell";
        description = "Working directory (project root) for opencode";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # ── Package ────────────────────────────────────────────────────
    environment.systemPackages = [
      unstable.opencode
    ];

    # ── Web interface systemd service ──────────────────────────────
    # Not auto-started — use `systemctl start opencode-web` when needed.
    systemd.services.opencode-web = lib.mkIf cfg.web.enable {
      description = "OpenCode Web Interface";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "crussell";
        Group = "users";
        WorkingDirectory = cfg.web.directory;
        ExecStart = "${unstable.opencode}/bin/opencode web --port ${toString cfg.web.port} --hostname ${cfg.web.hostname}";
        Restart = "always";
        RestartSec = "5";
        StartLimitIntervalSec = "60";
        StartLimitBurst = "5";
      };
    };
  };
}

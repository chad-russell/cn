# ── Pipane: Web UI for the pi coding agent ─────────────────────────
#
# Runs pipane as a systemd service. pipane launches pi in RPC mode and
# streams agent messages to a browser UI over WebSocket.
#
# A fixed auth token is auto-generated on first activation and stored at
# /etc/pipane/auth.env. Visit https://<host>/auth?token=<TOKEN> to
# authenticate (cookie lasts 30 days).
#
# Environment variables:
#   PIPANE_AUTH_TOKEN     — set via /etc/pipane/auth.env
#   PIPANE_DISABLE_LOCAL_BYPASS=1 — always require auth (even localhost)
#   PIPANE_SECURE_COOKIE=1  — set Secure flag on cookies (Caddy does TLS)
#   PORT                  — pipane listen port (default 8222)
#   PI_CWD                — default working directory for pi sessions

{ config, lib, pkgs, ... }:

let
  cfg = config.services.pipane;
  nodejs = pkgs.nodejs;
in
{
  options.services.pipane = {
    enable = lib.mkEnableOption "pipane web UI for pi coding agent";

    port = lib.mkOption {
      type = lib.types.int;
      default = 8222;
      description = "Port for pipane to listen on.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "crussell";
      description = "User to run pipane as (needs home dir for npm cache + pi sessions).";
    };

    workingDir = lib.mkOption {
      type = lib.types.path;
      default = "/home/crussell";
      description = "Default working directory for pi sessions.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to open the firewall for the pipane port.";
    };
  };

  config = lib.mkIf cfg.enable {

    # ── Auto-generate a fixed auth token on first activation ──────
    system.activationScripts.pipane-auth = lib.stringAfter [ "users" ] ''
      if [ ! -f /etc/pipane/auth.env ]; then
        mkdir -p /etc/pipane
        TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '/+=\n' | head -c 32)
        printf 'PIPANE_AUTH_TOKEN=%s\n' "$TOKEN" > /etc/pipane/auth.env
        chmod 600 /etc/pipane/auth.env
      fi
    '';

    # ── Systemd service ──────────────────────────────────────────
    systemd.services.pipane = {
      description = "Pipane — Web UI for pi coding agent";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        PORT = toString cfg.port;
        PI_CWD = cfg.workingDir;
        NODE_ENV = "production";
        PIPANE_DISABLE_LOCAL_BYPASS = "1";
        PIPANE_SECURE_COOKIE = "1";
      };

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        ExecStart = "${lib.getBin nodejs}/bin/npx pipane";
        Environment = [
          "PATH=/run/current-system/sw/bin:${lib.getBin nodejs}/bin"
        ];
        # Leading '-' means: don't fail if file is missing on first boot
        # (activation script will create it; pipane falls back to random token)
        EnvironmentFile = "-/etc/pipane/auth.env";
        Restart = "on-failure";
        RestartSec = "5";
        WorkingDirectory = cfg.workingDir;
      };
    };

    # ── Firewall ─────────────────────────────────────────────────
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}

# ── Gloo AI Proxy ──────────────────────────────────────────────────────
#
# Runs an OpenAI-compatible proxy that translates requests to the Gloo AI
# platform.  Pi, opencode, and any OpenAI client can point at
# http://localhost:4637/v1 to use Gloo models.
#
# Usage (in a host configuration.nix or home.nix):
#   services.gloo-proxy = {
#     enable = true;
#     user = "crussell";
#   };

{ config, lib, pkgs, ... }:

let
  cfg = config.services.gloo-proxy;
in
{
  options.services.gloo-proxy = {
    enable = lib.mkEnableOption "Gloo AI OpenAI-compatible proxy";

    package = lib.mkPackageOption pkgs "gloo-proxy" { };

    port = lib.mkOption {
      type = lib.types.port;
      default = 4637;
      description = "Port for the proxy to listen on";
    };

    user = lib.mkOption {
      type = lib.types.str;
      description = "User to run the service as";
    };
  };

  config = lib.mkIf cfg.enable {

    # ── Systemd user service ─────────────────────────────────────────
    systemd.services."gloo-proxy" = {
      description = "Gloo AI OpenAI-compatible proxy";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/gloo-proxy";
        Environment = "PORT=${toString cfg.port}";
        User = cfg.user;
        Group = "users";
        Restart = "on-failure";
        RestartSec = 5;

        # Security hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateTmp = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
        LockPersonality = true;
        MemoryDenyWriteExecute = false; # Bun JIT needs this
      };
    };
  };
}

# ── Gloo AI Proxy (bees) ─────────────────────────────────────────────
#
# OpenAI-compatible proxy that translates requests to the Gloo AI
# platform. opencode (and any OpenAI client) can point at
# http://localhost:4637/v1 to use Gloo models.
#
# Credentials: the proxy first tries the per-request
# `Authorization: Bearer <client_id>:<client_secret>` header; if absent it
# falls back to the ambient GLOO_AI_CLIENT_ID / GLOO_AI_CLIENT_SECRET env
# vars, supplied here via the agenix secret secrets/gloo-credentials.age
# (an env file with those two keys).

{ config, lib, pkgs, ... }:

let
  cfg = config.services.gloo-proxy;
  gloo-proxy = pkgs.callPackage ./gloo-proxy/package.nix { };
in
{
  options.services.gloo-proxy = {
    enable = lib.mkEnableOption "Gloo AI OpenAI-compatible proxy";

    port = lib.mkOption {
      type = lib.types.port;
      default = 4637;
      description = "Port for the proxy to listen on";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "crussell";
      description = "User to run the service as";
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets.gloo-credentials.file = ../../secrets/gloo-credentials.age;

    systemd.services."gloo-proxy" = {
      description = "Gloo AI OpenAI-compatible proxy";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${gloo-proxy}/bin/gloo-proxy";
        Environment = [ "PORT=${toString cfg.port}" ];
        # Provides GLOO_AI_CLIENT_ID / GLOO_AI_CLIENT_SECRET (env file).
        EnvironmentFile = config.age.secrets.gloo-credentials.path;
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

# ── Caddy Dev Reverse Proxy on bee ────────────────────────────────
#
# Terminates TLS for *.dev.crussell.io using Caddy's internal CA.
# Routes to localhost dev services running on bee.
#
# The internal CA root cert must be trusted on client machines:
#   1. Extract:  cat /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt
#   2. Trust on NixOS laptop: security.pki.certificateFiles
#
# Architecture:
#   browser → AdGuardHome (10.10.0.12) → *.dev.crussell.io → 10.10.0.12
#           → Caddy on bee (443) → localhost:PORT

{ config, lib, pkgs, ... }:

{
  services.caddy = {
    enable = true;

    # Listen on Nebula IP and localhost so dev services are reachable
    # from both Nebula clients and local processes.
    virtualHosts = {
      # ── Gloo dev stack ──────────────────────────────────────────

      "gpl.dev.crussell.io" = {
        extraConfig = ''
          tls internal
          reverse_proxy localhost:3106
        '';
      };

      "hb-api.dev.crussell.io" = {
        extraConfig = ''
          tls internal
          reverse_proxy localhost:8000
        '';
      };

      "hb-web.dev.crussell.io" = {
        extraConfig = ''
          tls internal
          reverse_proxy localhost:3100
        '';
      };

      "polymer.dev.crussell.io" = {
        extraConfig = ''
          tls internal
          reverse_proxy localhost:3001
        '';
      };

      "storyhub.dev.crussell.io" = {
        extraConfig = ''
          tls internal
          reverse_proxy localhost:3007
        '';
      };

      "rustfs.dev.crussell.io" = {
        extraConfig = ''
          tls internal
          reverse_proxy localhost:9000
        '';
      };

      "rustfs-console.dev.crussell.io" = {
        extraConfig = ''
          tls internal
          redir / /rustfs/console/index.html
          reverse_proxy localhost:9001
        '';
      };

      "pgadmin.dev.crussell.io" = {
        extraConfig = ''
          tls internal
          reverse_proxy localhost:5050
        '';
      };

      # ── Buildspace dev stack ────────────────────────────────────

      "buildspace.dev.crussell.io" = {
        extraConfig = ''
          tls internal
          reverse_proxy localhost:3000
        '';
      };

      "bs-login.dev.crussell.io" = {
        extraConfig = ''
          tls internal
          reverse_proxy localhost:3003
        '';
      };

      "bs-creator.dev.crussell.io" = {
        extraConfig = ''
          tls internal
          reverse_proxy localhost:3005
        '';
      };

      "bs-api.dev.crussell.io" = {
        extraConfig = ''
          tls internal
          reverse_proxy localhost:3002
        '';
      };

      "bs-docs.dev.crussell.io" = {
        extraConfig = ''
          tls internal
          reverse_proxy localhost:3004
        '';
      };

      "bs-admin.dev.crussell.io" = {
        extraConfig = ''
          tls internal
          reverse_proxy localhost:3006
        '';
      };

      "bs-jobs.dev.crussell.io" = {
        extraConfig = ''
          tls internal
          reverse_proxy localhost:3010
        '';
      };
    };
  };

  # Caddy needs 80/443 open for HTTPS (and HTTP→HTTPS redirect)
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}

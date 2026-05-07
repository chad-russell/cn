# ── AdGuard Home DNS on bee ────────────────────────────────────────
#
# Self-hosted DNS for the dev overlay network.
# Serves DNS rewrites for *.dev.crussell.io → bee's Nebula IP.
#
# Access:
#   DNS queries:  10.10.0.12:53 (Nebula only — not exposed on LAN)
#   Web admin:    10.10.0.12:3000 (Nebula only)
#
# The split DNS on the laptop routes *.dev.crussell.io to this server.
# Caddy on bee then reverse-proxies individual hostnames to localhost ports.
#
# NOTE: mutableSettings is false — config is fully declarative via Nix.
# Changes made in the web admin UI will be overwritten on next deploy.

{ config, lib, pkgs, ... }:

{
  services.adguardhome = {
    enable = true;
    host = "10.10.0.12";   # Nebula IP only — not reachable from LAN/internet
    port = 3000;            # Web admin UI (via Nebula only)

    mutableSettings = false; # Fully declarative — avoids yaml-merge disabling rewrites

    settings = {
      dns = {
        # Listen on Nebula IP only, port 53
        bind_hosts = [ "10.10.0.12" ];
        port = 53;

        upstream_dns = [
          "8.8.8.8"
          "1.1.1.1"
        ];
        bootstrap_dns = [
          "8.8.8.8"
          "1.1.1.1"
        ];
      };

      filtering = {
        protection_enabled = true;
        filtering_enabled = true;

        # DNS rewrites: *.dev.crussell.io → bee's Nebula IP
        # Caddy on bee handles hostname-based routing to individual services.
        rewrites = [
          # Gloo dev stack
          { domain = "gpl.dev.crussell.io";          answer = "10.10.0.12"; enabled = true; }
          { domain = "hb-api.dev.crussell.io";        answer = "10.10.0.12"; enabled = true; }
          { domain = "hb-web.dev.crussell.io";        answer = "10.10.0.12"; enabled = true; }
          { domain = "polymer.dev.crussell.io";       answer = "10.10.0.12"; enabled = true; }
          { domain = "storyhub.dev.crussell.io";      answer = "10.10.0.12"; enabled = true; }
          { domain = "rustfs.dev.crussell.io";         answer = "10.10.0.12"; enabled = true; }
          { domain = "rustfs-console.dev.crussell.io"; answer = "10.10.0.12"; enabled = true; }
          { domain = "pgadmin.dev.crussell.io";        answer = "10.10.0.12"; enabled = true; }

          # Buildspace dev stack
          { domain = "buildspace.dev.crussell.io";     answer = "10.10.0.12"; enabled = true; }
          { domain = "bs-login.dev.crussell.io";       answer = "10.10.0.12"; enabled = true; }
          { domain = "bs-creator.dev.crussell.io";     answer = "10.10.0.12"; enabled = true; }
          { domain = "bs-api.dev.crussell.io";         answer = "10.10.0.12"; enabled = true; }
          { domain = "bs-docs.dev.crussell.io";        answer = "10.10.0.12"; enabled = true; }
          { domain = "bs-admin.dev.crussell.io";       answer = "10.10.0.12"; enabled = true; }
          { domain = "bs-jobs.dev.crussell.io";        answer = "10.10.0.12"; enabled = true; }
        ];
      };
    };
  };

  # Open DNS port (UDP+TCP 53) and web admin (TCP 3000) on the host firewall.
  # Nebula has its own firewall that already allows all traffic.
  networking.firewall.allowedTCPPorts = [ 53 3000 ];
  networking.firewall.allowedUDPPorts = [ 53 ];
}

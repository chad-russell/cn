{ config, lib, pkgs, ... }:

{
  imports = [
    ../../modules/base-server.nix
    # Hub has different hardware — no elitedesk module
  ];

  networking.hostName = "hub";

  # ── Networking ───────────────────────────────────────────────────
  # Hub is currently Fedora Atomic — will be filled in during migration.
  # For now, placeholder that matches current setup.
  systemd.network.networks."40-eno1" = {
    matchConfig.Name = "eno1";
    networkConfig.DHCP = "no";
    address = [ "192.168.20.105/24" ];
    routes = [{ Gateway = "192.168.20.1"; }];
    dns = [ "8.8.8.8" "1.1.1.1" ];
  };

  # ── TODO: Add these during hub migration ─────────────────────────
  # - Caddy reverse proxy (with all routes)
  # - Nebula (lighthouse + host identity — dual config)
  # - Restic backup system
  # - Container services (linkding, papra, ntfy, open-webui, etc.)
  # - Gloo dev stack (if staying on hub)
  # - Immich (if staying on hub)

  # ── State version ───────────────────────────────────────────────
  system.stateVersion = "25.11";
}

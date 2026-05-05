# ── Ntfy Push Notifications ──────────────────────────────────────
#
# Native NixOS ntfy-sh service.
# Migrated from hub's Podman container — cache is transient, no data to migrate.

{ config, lib, pkgs, ... }:

{
  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://ntfy.internal.crussell.io";
      listen-http = "0.0.0.0:8090";
      behind-proxy = true;
      cache-file = "/var/lib/ntfy-sh/cache.db";
      attachment-cache-dir = "/var/lib/ntfy-sh/attachments";
    };
  };

  # Ensure attachment dir exists (ntfy won't create it on first run)
  systemd.services.ntfy-sh.serviceConfig.CacheDirectory = "ntfy-sh";

  # Caddy on hub proxies to this port
  networking.firewall.allowedTCPPorts = [ 8090 ];
}

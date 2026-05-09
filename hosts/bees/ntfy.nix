# ── Ntfy Push Notifications ──────────────────────────────────────

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

  systemd.services.ntfy-sh.serviceConfig.CacheDirectory = "ntfy-sh";
  networking.firewall.allowedTCPPorts = [ 8090 ];
}

# ── Nebula VPN Client Module ───────────────────────────────────────
#
# Standard Nebula client config for homelab machines.
# Lighthouses: 10.10.0.1 (k2 local) and 10.10.0.2 (Hetzner)
#
# Usage in host config:
#   imports = [ ./modules/nebula-client.nix ];
#   services.nebula.networks.homelab.enable = true;
#   # Then place certs at /etc/nebula/{ca.crt,host.crt,host.key}
#
# Certs are NOT managed by this module — deploy them separately
# (via agenix or manual copy) before enabling.
#
# This module sets connection defaults unconditionally.
# They're inert when enable = false (the default).

{ config, lib, pkgs, ... }:

{
  config = {
    services.nebula.networks.homelab = {
      ca = "/etc/nebula/ca.crt";
      cert = "/etc/nebula/host.crt";
      key = "/etc/nebula/host.key";

      staticHostMap = {
        "10.10.0.1" = [ "192.168.20.105:4243" ];
        "10.10.0.2" = [ "178.156.171.212:4242" ];
      };

      isLighthouse = false;
      isRelay = false;
      lighthouses = [ "10.10.0.1" "10.10.0.2" ];
      relays = [ "10.10.0.2" ];

      listen.host = "0.0.0.0";
      listen.port = null;

      tun.disable = false;

      firewall.outbound = [{ port = "any"; proto = "any"; host = "any"; }];
      firewall.inbound  = [{ port = "any"; proto = "any"; host = "any"; }];

      settings = {
        punchy = { punch = true; respond = true; };
        preferred_ranges = [ "192.168.20.0/24" ];
        logging = { level = "info"; format = "text"; };
        lighthouse.interval = 60;
        firewall.conntrack = {
          tcp_timeout = "120h";
          udp_timeout = "3m";
          default_timeout = "10m";
          max_connections = 100000;
        };
      };
    };

    # Ensure nebula service user can read cert files when enabled
    systemd.tmpfiles.rules = lib.mkIf config.services.nebula.networks.homelab.enable [
      "Z /etc/nebula/ca.crt  0440 root nebula-homelab -"
      "Z /etc/nebula/host.crt 0440 root nebula-homelab -"
      "Z /etc/nebula/host.key 0440 root nebula-homelab -"
    ];
  };
}

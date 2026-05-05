{ config, lib, pkgs, ... }:

{
  imports = [
    ../../modules/elitedesk-hardware.nix
    ../../modules/base-server.nix
    ../../modules/elitedesk-disk-config.nix
    ../../modules/nebula-client.nix
    ./ntfy.nix
    ./searxng.nix
    ./datenight.nix
    ./caddy.nix
    ./hub-services.nix
  ];

  networking.hostName = "k2";

  # ── Networking ───────────────────────────────────────────────────
  systemd.network.networks."40-eno1" = {
    matchConfig.Name = "eno1";
    networkConfig.DHCP = "no";
    address = [ "192.168.20.62/24" ];
    routes = [{ Gateway = "192.168.20.1"; }];
    dns = [ "8.8.8.8" "1.1.1.1" ];
  };

  # ── NFS: Backups from NAS ───────────────────────────────────────
  fileSystems."/mnt/backups" = {
    device = "192.168.20.31:/mnt/tank/backups";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "timeo=14" "nfsvers=4" "rw" "soft" "intr" ];
  };

  # ── Nebula: Host identity (10.10.0.6 — migrated from hub) ──────
  #
  # k2 assumes hub's nebula identity as the services endpoint.
  # This means Hetzner and all clients continue targeting 10.10.0.6
  # and traffic lands here instead of the old hub.
  #
  # The lighthouse static_host_map for 10.10.0.1 points to localhost:4243
  # (the co-located local lighthouse instance below).

  services.nebula.networks.homelab = {
    enable = true;

    # Use hub's certs (10.10.0.6 identity)
    ca = "/etc/nebula/ca.crt";
    cert = "/etc/nebula/host.crt";
    key = "/etc/nebula/host.key";

    staticHostMap = {
      "10.10.0.1" = [ "127.0.0.1:4243" "192.168.20.62:4243" ];
      "10.10.0.2" = [ "178.156.171.212:4242" ];
    };

    lighthouses = [ "10.10.0.1" "10.10.0.2" ];
  };

  # ── Nebula: Local lighthouse (10.10.0.1 — migrated from hub) ───
  #
  # Runs a second nebula instance as the local lighthouse on port 4243.
  # Uses tun.disabled = true (discovery only, no tunnel interface).
  # Certs live in /etc/nebula-lh/.

  services.nebula.networks.lighthouse = {
    enable = true;

    ca = "/etc/nebula-lh/ca.crt";
    cert = "/etc/nebula-lh/host.crt";
    key = "/etc/nebula-lh/host.key";

    isLighthouse = true;

    listen.host = "0.0.0.0";
    listen.port = 4243;

    tun.disable = true;

    firewall.outbound = [{ port = "any"; proto = "any"; host = "any"; }];
    firewall.inbound  = [{ port = "any"; proto = "any"; host = "any"; }];

    settings = {
      logging = { level = "info"; format = "text"; };
      punchy = { punch = true; respond = true; };
      firewall.conntrack = {
        tcp_timeout = "120h";
        udp_timeout = "3m";
        default_timeout = "10m";
        max_connections = 100000;
      };
    };
  };

  # Ensure lighthouse cert permissions
  systemd.tmpfiles.rules = [
    "Z /etc/nebula-lh/ca.crt  0440 root nebula-lighthouse -"
    "Z /etc/nebula-lh/host.crt 0440 root nebula-lighthouse -"
    "Z /etc/nebula-lh/host.key 0440 root nebula-lighthouse -"
  ];

  # ── Firewall: public ingress + local lighthouse ─────────────────
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  networking.firewall.allowedUDPPorts = [ 4242 4243 ];

  # ── Podman (for Caddy container) ────────────────────────────────
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  # ── State version ───────────────────────────────────────────────
  system.stateVersion = "25.05";
}

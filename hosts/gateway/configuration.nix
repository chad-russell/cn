# ── gateway: Hetzner Cloud Reverse Proxy ───────────────────────────
#
# Public VPS at 178.156.171.212 (Hetzner Cloud x86_64)
# Caddy terminates TLS for *.crussell.io and reverse-proxies to backends
# over the Nebula overlay (native NixOS Caddy, Let's Encrypt HTTP-01).
# Nebula lighthouse + relay: 10.10.0.2, UDP 4242
#
# Install with nixos-anywhere (preserves the existing public IP):
#   nix run .#install -- gateway

{ config, lib, pkgs, ... }:

{
  imports = [
    ./disk-config.nix
    ./caddy.nix
    ../../modules/base-server.nix
    # NOTE: Do NOT import nebula-client.nix — this host IS a lighthouse.
    # Nebula is configured manually below with lighthouse/relay overrides.
  ];

  networking.hostName = "gateway";

  # ── Boot (Hetzner Cloud x86_64 uses legacy BIOS) ────────────────
  # GRUB device is auto-configured by disko (EF02 BIOS boot partition)
  boot.loader.grub.enable = true;

  boot.initrd.availableKernelModules = [
    "ahci" "xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod"
  ];

  # ── Hardware ─────────────────────────────────────────────────────
  hardware.enableRedistributableFirmware = true;

  # ── Networking ───────────────────────────────────────────────────
  # Hetzner Cloud: DHCP provides the public IPv4 address.
  # NixOS with systemd predictable naming renames eth0 → enp1s0.
  # Verified via journal: "eth0: Interface name change detected, renamed to enp1s0"
  # MAC matching (like bees) would also work: matchConfig.MACAddress = "96:00:04:54:03:9b";
  systemd.network.networks."40-wan" = {
    matchConfig.Name = "enp1s0";
    networkConfig.DHCP = "ipv4";
    dns = [ "8.8.8.8" "1.1.1.1" ];
  };

  # ── SSH ──────────────────────────────────────────────────────────
  # Public-facing host — disable password auth (override base-server.nix).
  # Also add the RSA key from the thinkpad for redundancy.
  services.openssh.settings.PasswordAuthentication = lib.mkForce false;
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDsHOYNAog8L5SAhKp551g4oJFSi/GB+Fg38mmBLhwbrCUSfVSFqKeaOuRlLCQVnTWPZYfyp6cTibHBeigky6fjKhQgKnUJgwPdHjxhSvk7m6zgGj71s45bFT918E1J8hysN2wrijoo6oJ1zSeX3FIWOcFZVR4MHxCdYCMr+4mJp8tb1oQRea6GxCFGCms7DoNii+gWL/K2KZTMHKZ6l9Nf5CXq/6+a9Pfog3XuRlpTxLlIVj8YMC8TeRki0m9mG4+gk4OtCzACL/ngY0OxRWN4IN0NhFZOO5FHwytMR9/yNiAzafzaIt2szd69nmPG3DrXSUN1nXZKR78kM5O1kIaEKNeWJjhTXuDF7DtMF61TlXDWmsFxQbF9TAWK7nXJMUzAgXY1vIkTiYV3uwBB9upyKmXD/M5U1cFDvY6sSnINHxaqXp7/IoEHsXzHKmR5yhGLVszMzMlINBTxrWEYbjzNJPEvWeLCt3EbU4LPVffc8MA+l9zujSDjMO78uC7k/Ek="
  ];
  users.users.crussell.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDsHOYNAog8L5SAhKp551g4oJFSi/GB+Fg38mmBLhwbrCUSfVSFqKeaOuRlLCQVnTWPZYfyp6cTibHBeigky6fjKhQgKnUJgwPdHjxhSvk7m6zgGj71s45bFT918E1J8hysN2wrijoo6oJ1zSeX3FIWOcFZVR4MHxCdYCMr+4mJp8tb1oQRea6GxCFGCms7DoNii+gWL/K2KZTMHKZ6l9Nf5CXq/6+a9Pfog3XuRlpTxLlIVj8YMC8TeRki0m9mG4+gk4OtCzACL/ngY0OxRWN4IN0NhFZOO5FHwytMR9/yNiAzafzaIt2szd69nmPG3DrXSUN1nXZKR78kM5O1kIaEKNeWJjhTXuDF7DtMF61TlXDWmsFxQbF9TAWK7nXJMUzAgXY1vIkTiYV3uwBB9upyKmXD/M5U1cFDvY6sSnINHxaqXp7/IoEHsXzHKmR5yhGLVszMzMlINBTxrWEYbjzNJPEvWeLCt3EbU4LPVffc8MA+l9zujSDjMO78uC7k/Ek="
  ];

  # ── Nebula: Lighthouse + Relay ──────────────────────────────────
  #
  # Public lighthouse/relay for the Nebula overlay mesh.
  # All LAN nodes use 10.10.0.2 as their public lighthouse endpoint.
  #
  # Certs must be placed at /etc/nebula/{ca.crt,host.crt,host.key}
  # after initial install (scp via public IP):
  #
  #   scp nebula/pki/ca.crt root@178.156.171.212:/etc/nebula/ca.crt
  #   scp nebula/pki/hetzner-lighthouse.crt root@178.156.171.212:/etc/nebula/host.crt
  #   age -d -i ~/.ssh/id_ed25519 nebula/pki/hetzner-lighthouse.key.age | \
  #     ssh root@178.156.171.212 'cat > /etc/nebula/host.key'
  #
  services.nebula.networks.homelab = {
    enable = true;

    ca = "/etc/nebula/ca.crt";
    cert = "/etc/nebula/host.crt";
    key = "/etc/nebula/host.key";

    isLighthouse = true;
    isRelay = true;

    # No upstream lighthouses — this IS the public lighthouse.
    # Nodes discover it via their staticHostMap entries for 10.10.0.2.
    lighthouses = [];
    relays = [];
    staticHostMap = {};

    listen.host = "0.0.0.0";
    listen.port = 4242;

    tun.disable = false;

    firewall.outbound = [{ port = "any"; proto = "any"; host = "any"; }];
    firewall.inbound  = [{ port = "any"; proto = "any"; host = "any"; }];

    settings = {
      punchy = { punch = true; respond = true; };
      logging = { level = "info"; format = "text"; };
      lighthouse.interval = 60;
      firewall.conntrack = {
        tcp_timeout = "12m";
        udp_timeout = "3m";
        default_timeout = "10m";
        max_connections = 100000;
      };
    };
  };

  # Nebula cert permissions
  systemd.tmpfiles.rules = [
    "Z /etc/nebula/ca.crt  0440 root nebula-homelab -"
    "Z /etc/nebula/host.crt 0440 root nebula-homelab -"
    "Z /etc/nebula/host.key 0440 root nebula-homelab -"
  ];

  # ── Firewall ─────────────────────────────────────────────────────
  # 80/443 for Caddy (TLS + HTTP-01 challenge); no more 8080 health endpoint
  # (that was nginx-only and nothing scraped it).
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];
  networking.firewall.allowedUDPPorts = [ 4242 ];

  # ── State version ───────────────────────────────────────────────
  system.stateVersion = "25.11";
}

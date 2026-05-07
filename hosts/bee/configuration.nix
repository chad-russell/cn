# ── bee: Beelink Mini PC ───────────────────────────────────────────
#
# NixOS install on Crucial P3 Plus 1TB NVMe, 32GB RAM.
# General-purpose server — services to be added incrementally.

{ config, lib, pkgs, ... }:

{
  imports = [
    ../../modules/base-server.nix
    ../../modules/hub-disk-config.nix
    ../../modules/nebula-client.nix
    ./adguardhome.nix
    ./caddy-dev.nix
    ./gloo.nix
    ./gloo-containerized.nix
    ./buildspace.nix
  ];

  networking.hostName = "bee";

  # ── Boot ─────────────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];

  # ── Hardware ─────────────────────────────────────────────────────
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.enableRedistributableFirmware = true;
  zramSwap.enable = true;

  # ── Networking ───────────────────────────────────────────────────
  systemd.network.networks."40-enp1s0" = {
    matchConfig.Name = "enp1s0";
    networkConfig.DHCP = "no";
    address = [ "192.168.20.105/24" ];
    routes = [{ Gateway = "192.168.20.1"; }];
    dns = [ "8.8.8.8" "1.1.1.1" ];
  };

  # ── NFS: Backups from NAS ───────────────────────────────────────
  fileSystems."/mnt/backups" = {
    device = "192.168.20.31:/mnt/tank/backups";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "timeo=14" "nfsvers=4" "rw" "soft" "intr" ];
  };

  # ── Nebula ──────────────────────────────────────────────────────
  services.nebula.networks.homelab.enable = true;

  # ── Nebula: Local lighthouse (10.10.0.1) ───────────────────────
  #
  # Migrated from k2. Runs a second nebula instance as the local
  # lighthouse on port 4243. Uses tun.disabled = true (discovery only).
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

  # Lighthouse needs UDP 4243 open
  networking.firewall.allowedUDPPorts = [ 4243 ];

  # ── Dev tools ───────────────────────────────────────────────────
  environment.systemPackages = [
    pkgs.git
    pkgs.github-cli
  ];

  # Firewall ports managed by gloo-containerized and buildspace modules

  # ── Dev stacks ──────────────────────────────────────────────────
  # Native Gloo disabled — migrated to containerized stack.
  # services.gloo.enable = true;
  services.gloo-containerized.enable = true;
  services.buildspace.enable = true;

  # ── State version ───────────────────────────────────────────────
  system.stateVersion = "25.11";
}

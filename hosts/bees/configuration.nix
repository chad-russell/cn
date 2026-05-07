# ── bees: AMD Ryzen AI MAX+ 395 Production Server ──────────────────
#
# AMD Ryzen AI MAX+ 395 w/ Radeon 8060S, 16C/32T
# 128 GB RAM (shared with iGPU; ~32 GB visible to OS)
# 2 TB NVMe (Crucial P310), dual Intel E610 10GbE
# Active NIC: enp196s0f1 (second port; enp196s0f0 is unplugged)
#
# Target: consolidate all services from k2, k3, k4 onto this machine.

{ config, lib, pkgs, unstable, ... }:

{
  imports = [
    ../../modules/base-server.nix
    ./disk-config.nix
    ../../modules/nebula-client.nix
    ./media-services.nix
    ./immich.nix
    ./ntfy.nix
    ./searxng.nix
    ./datenight.nix
    ./caddy.nix
    ./hub-services.nix
    ./backup.nix
  ];

  networking.hostName = "bees";

  # ── Essential packages ────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    # AI / dev tools
    unstable."pi-coding-agent"
  ];

  # ── Boot ─────────────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usbhid"
    "sd_mod"
    # Intel E610 10GbE NIC driver
    "ixgbe"
  ];
  boot.initrd.kernelModules = [ "ixgbe" ];
  boot.kernelModules = [ "kvm-amd" ];

  # Use latest kernel (7.0.x) — the default 6.12 ixgbe module doesn't
  # recognize the Intel E610 (8086:57b0) NIC on this machine.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # ── Hardware ─────────────────────────────────────────────────────
  nixpkgs.config.allowUnfree = true;

  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.enableRedistributableFirmware = lib.mkForce true;
  hardware.enableAllFirmware = true;
  zramSwap.enable = true;

  # ── Networking ───────────────────────────────────────────────────
  # Intel E610 dual-port 10GbE — active port is the second function
  # PCI slot: 0000:c4:00.1, MAC: 78:55:36:02:ce:bf
  #
  # Match by MAC address so the network comes up regardless of what
  # predictable name systemd-udevd assigns.
  systemd.network.networks."40-lan" = {
    matchConfig.MACAddress = "78:55:36:02:ce:bf";
    networkConfig.DHCP = "no";
    address = [ "192.168.20.41/24" ];
    routes = [{ Gateway = "192.168.20.1"; }];
    dns = [ "8.8.8.8" "1.1.1.1" ];
  };

  # ── NFS: Media from NAS ─────────────────────────────────────────
  fileSystems."/mnt/media" = {
    device = "192.168.20.31:/mnt/tank/media";
    fsType = "nfs";
    options = [ "defaults" "_netdev" "rw" "hard" "intr" ];
  };

  # ── NFS: Photos from NAS ────────────────────────────────────────
  fileSystems."/mnt/photos" = {
    device = "192.168.20.31:/mnt/tank/photos";
    fsType = "nfs";
    options = [ "defaults" "_netdev" "rw" "hard" "intr" ];
  };

  # ── NFS: Backups from NAS ───────────────────────────────────────
  fileSystems."/mnt/backups" = {
    device = "192.168.20.31:/mnt/tank/backups";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "timeo=14" "nfsvers=4" "rw" "soft" "intr" ];
  };

  # ── Nebula ──────────────────────────────────────────────────────
  services.nebula.networks.homelab.enable = true;

  # ── Firewall: public ingress for Caddy ──────────────────────────
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  networking.firewall.allowedUDPPorts = [ 4242 ];

  # ── Podman (for Caddy + hub service containers) ─────────────────
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  # ── State version ───────────────────────────────────────────────
  system.stateVersion = "25.11";
}

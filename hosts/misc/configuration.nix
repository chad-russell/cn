# ── misc: HP Z820 Workstation ──────────────────────────────────────
#
# Temporary role: backup target for TrueNAS → NAS migration.
# Future role: NixOS hypervisor (VMs, Kubernetes) — will be nuked
# and re-laid-out when NVMe adapters arrive.
#
# Hardware:
#   - HP Z820 workstation
#   - Intel Xeon (Sandy Bridge/Ivy Bridge era)
#   - Gigabit Ethernet
#   - 2× 2TB SATA SSD, 2× 4TB HDD
#
# Storage:
#   SSD 1: NixOS root (btrfs)
#   SSD 2: /mnt/extra (btrfs)
#   HDD 1+2: /mnt/backup — btrfs single pool (~8TB)
#
# Network: DHCP (temporary machine, exact NIC name unknown)

{ config, lib, pkgs, ... }:

{
  imports = [
    ../../modules/base-server.nix
    ./disk-config.nix
    ../../modules/nebula-client.nix
  ];

  networking.hostName = "misc";

  # ── Boot ─────────────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # HP Z820 has Intel C600 series chipset
  boot.initrd.availableKernelModules = [
    "isci"           # Intel C602 SAS controller — all disks are on this
    "mpt3sas"        # LSI SAS2008 — also used by C602 SAS
    "ahci"
    "sd_mod"
    "sr_mod"
    "ehci_pci"
    "xhci_pci"
    "usbhid"
    "nvme"          # for future NVMe adapters
  ];
  boot.initrd.kernelModules = [
    "isci"           # Must be loaded early — root filesystem is on this controller
    "mpt3sas"
  ];
  boot.kernelModules = [ "kvm-intel" ];

  # ── Hardware ─────────────────────────────────────────────────────
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.enableRedistributableFirmware = true;
  zramSwap.enable = true;

  # ── Networking ───────────────────────────────────────────────────
  systemd.network.networks."40-enp1s0" = {
    matchConfig.Name = "enp1s0";
    networkConfig.DHCP = "no";
    address = [ "192.168.20.42/24" ];
    routes = [{ Gateway = "192.168.20.1"; }];
    dns = [ "8.8.8.8" "1.1.1.1" ];
  };

  # ── Nebula ──────────────────────────────────────────────────────
  # Certs must be deployed to /etc/nebula/{ca.crt,host.crt,host.key}
  # before enabling. Generate from nebula/pki/ CA:
  #   nebula cert sign -ca-crt nebula/pki/ca.crt -ca-key <decrypted> \
  #     -out misc.crt -ip "10.10.0.11/24" -name "misc"
  services.nebula.networks.homelab.enable = false;  # enable after certs are in place

  # ── NFS mounts from TrueNAS (for Phase 2: rsync backup) ────────
  fileSystems."/mnt/truenas-media" = {
    device = "192.168.20.31:/mnt/tank/media";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "timeo=14" "nfsvers=4" "ro" ];
  };
  fileSystems."/mnt/truenas-photos" = {
    device = "192.168.20.31:/mnt/tank/photos";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "timeo=14" "nfsvers=4" "ro" ];
  };
  fileSystems."/mnt/truenas-w" = {
    device = "192.168.20.31:/mnt/tank/w";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "timeo=14" "nfsvers=4" "ro" ];
  };
  fileSystems."/mnt/truenas-backups" = {
    device = "192.168.20.31:/mnt/tank/backups";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "timeo=14" "nfsvers=4" "ro" ];
  };

  # ── Backup pool directories ─────────────────────────────────────
  # Created on first deploy. These live on /mnt/backup (btrfs HDD pool).
  systemd.tmpfiles.rules = [
    "d /mnt/backup/photos    0755 crussell users -"
    "d /mnt/backup/media     0755 crussell users -"
    "d /mnt/backup/w         0755 crussell users -"
    "d /mnt/backup/backups   0755 crussell users -"
  ];

  # ── Extra packages for migration work ───────────────────────────
  environment.systemPackages = with pkgs; [
    rsync
    tmux
    tree
    pigz            # parallel gzip for faster transfers
    pv              # pipe viewer for progress
  ];

  # ── State version ───────────────────────────────────────────────
  system.stateVersion = "25.11";
}

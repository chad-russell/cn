# ── nas: UGREEN DXP4800 Pro ────────────────────────────────────────
#
# Network-attached storage server. Replaces TrueNAS (ZFS) with NixOS + btrfs.
#
# Hardware:
#   - UGREEN NAS DXP4800 Pro
#   - Intel Core i3-1315U (2P cores @ 4.5GHz + 4E cores @ 3.4GHz)
#   - 8GB DDR5 5600 (expandable to 96GB)
#   - 128GB onboard SSD
#   - 2× M.2 NVMe SSD slots (1 used for OS)
#   - 4× 3.5" SATA HDD bays (btrfs RAID1)
#   - 1× 10GbE (Intel?), 1× 2.5GbE (Intel i225-V?)
#   - 1× HDMI 4K output
#   - Multiple USB 3.x ports
#
# Storage layout:
#   NVMe: NixOS root (btrfs subvolumes)
#   4× HDD: btrfs RAID1 pool → /pool/{media,photos,surveillance,backups,scratch}
#
# Network:
#   10GbE:  static 192.168.20.31 (primary — NFS to bees/bee)
#   2.5GbE: DHCP fallback (unused unless 10GbE fails)
#
# Services:
#   - NFS server (exports to bees, bee)
#   - Monthly btrfs scrub + quarterly balance
#   - Nebula VPN client
#   - Prometheus node exporter

{ config, lib, pkgs, ... }:

{
  imports = [
    ../../modules/base-server.nix
    ./disk-config.nix
    ./nfs-exports.nix
    ./btrfs-maintenance.nix
    ../../modules/nebula-client.nix
  ];

  networking.hostName = "nas";

  # ── Boot ─────────────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Intel i3-1315U (Raptor Lake) — AHCI for SATA, NVMe for M.2
  boot.initrd.availableKernelModules = [
    "ahci"
    "nvme"
    "sd_mod"
    "xhci_pci"
    "usbhid"
    "sr_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];

  # ── Hardware ─────────────────────────────────────────────────────
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.enableRedistributableFirmware = true;
  zramSwap.enable = true;

  # ── Networking ───────────────────────────────────────────────────
  # TODO: Verify NIC names on first boot with `ip link`.
  # The 10GbE and 2.5GbE NICs may show as enp*s*f* or similar.
  # Adjust match patterns below to match reality.
  #
  # Primary: 10GbE port (NFS traffic to bees/bee)
  systemd.network.networks."40-10gbe" = {
    matchConfig.Name = "enp?*s0";    # TODO: update to actual NIC name
    # matchConfig.Path = "pci-0000:*";  # alternative: match by PCI path
    networkConfig.DHCP = "no";
    address = [ "192.168.20.31/24" ];  # Same IP as TrueNAS for drop-in replacement
    routes = [{ Gateway = "192.168.20.1"; }];
    dns = [ "8.8.8.8" "1.1.1.1" ];
  };

  # Secondary: 2.5GbE port (unused, DHCP as fallback)
  systemd.network.networks."41-2g5be" = {
    matchConfig.Name = "enp?*s1";    # TODO: update to actual NIC name
    networkConfig.DHCP = "yes";
  };

  # ── Nebula ──────────────────────────────────────────────────────
  # Keep the same Nebula IP as TrueNAS (10.10.0.3) for drop-in replacement.
  # Certs must be deployed to /etc/nebula/{ca.crt,host.crt,host.key}
  # before enabling. The existing TrueNAS nebula certs from nebula/pki/
  # should work — just deploy them to this host.
  services.nebula.networks.homelab.enable = false;  # enable after certs are in place

  # ── NFS: temporary mount of misc backup (for Phase 5: restore) ─
  # Enable during the restore phase, then disable.
  # fileSystems."/mnt/misc-backup" = {
  #   device = "192.168.20.42:/mnt/backup";
  #   fsType = "nfs";
  #   options = [ "x-systemd.automount" "noauto" "timeo=14" "nfsvers=4" "ro" ];
  # };

  # ── Pool directory structure ─────────────────────────────────────
  # Ensure top-level directories exist in each subvolume.
  # These are on the btrfs RAID1 data pool.
  systemd.tmpfiles.rules = [
    "d /pool/media/Downloads       0755 crussell users -"
    "d /pool/media/Movies          0755 crussell users -"
    "d /pool/media/TV              0755 crussell users -"
    "d /pool/media/Music           0755 crussell users -"
    "d /pool/surveillance          0755 crussell users -"
  ];

  # ── Extra packages ───────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    btrfs-progs
    smartmontools       # SMART disk health monitoring
    hdparm              # disk power management
    rsync
    tmux
    tree
    pciutils
    usbutils
  ];

  # ── SMART monitoring ─────────────────────────────────────────────
  # Enable smartd for early disk failure detection
  services.smartd = {
    enable = true;
    autodetect = true;
    notifications = {
      mail = {
        enable = false;  # TODO: enable with ntfy or email
      };
      test = true;       # send test notification on service start
    };
  };

  # ── SSH hardening (NAS holds all the data) ──────────────────────
  services.openssh.settings = {
    PasswordAuthentication = lib.mkForce false;  # Key-only — no passwords on the NAS
  };

  # ── State version ───────────────────────────────────────────────
  system.stateVersion = "25.11";
}

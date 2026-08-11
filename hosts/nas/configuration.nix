# ── nas: UGREEN DXP4800 ────────────────────────────────────────────
#
# Network-attached storage server. Replaces TrueNAS (ZFS) with NixOS + btrfs.
#
# Hardware:
#   - UGREEN NAS DXP4800 (Intel N100, 4C/4T)
#   - 32GB DDR5
#   - 128GB eMMC onboard (UGOS Pro — untouched)
#   - 1× M.2 NVMe SSD 512GB (SPCC) — NixOS root
#   - 4× 3.5" SATA HDD 12TB each (btrfs RAID1, ~12TB usable)
#   - 2× Intel I226-V 2.5GbE
#   - 1× HDMI 4K output
#   - Multiple USB 3.x ports
#
# Storage layout:
#   NVMe: NixOS root (btrfs subvolumes)
#   eMMC: UGOS Pro factory install (untouched)
#   4× HDD: btrfs RAID1 pool → /pool/{media,photos,surveillance,backups,scratch}
#
# Network:
#   enp3s0 (2.5GbE): static 192.168.20.31 — primary, NFS to bees/bee
#   enp2s0 (2.5GbE): DHCP — secondary/fallback
#
# Services:
#   - NFS server (exports to bees, bee)
#   - Monthly btrfs scrub + quarterly balance
#   - Nebula VPN client (10.10.0.3)

{ config, lib, pkgs, ... }:

{
  imports = [
    ../../modules/base-server.nix
    ../../modules/freshness-checks.nix
    ./disk-config.nix
    ./nfs-exports.nix
    ./samba.nix
    ./btrfs-maintenance.nix
    ../../modules/nebula-client.nix
    ../../modules/beszel-agent.nix
  ];

  networking.hostName = "nas";

  # ── Boot ─────────────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Intel N100 (Alder Lake-N)
  boot.initrd.availableKernelModules = [
    "ahci"
    "nvme"
    "sd_mod"
    "xhci_pci"
    "usbhid"
    "sr_mod"
    "mmc_block" # eMMC — don't mount, but detect to avoid confusion
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];

  # ── Hardware ─────────────────────────────────────────────────────
  hardware.cpu.intel.updateMicrocode =
    lib.mkDefault config.hardware.enableRedistributableFirmware;
  zramSwap.enable = true;

  # ── Networking ───────────────────────────────────────────────────
  # Primary NIC: enp3s0 (Intel I226-V, 2.5GbE) — static, same IP as TrueNAS
  systemd.network.networks."40-enp3s0" = {
    matchConfig.Name = "enp3s0";
    networkConfig.DHCP = "no";
    address = [ "192.168.20.31/24" ];
    routes = [{ Gateway = "192.168.20.1"; }];
    dns = [ "8.8.8.8" "1.1.1.1" ];
  };

  # Secondary NIC: enp2s0 (Intel I226-V, 2.5GbE) — DHCP fallback
  systemd.network.networks."41-enp2s0" = {
    matchConfig.Name = "enp2s0";
    networkConfig.DHCP = "yes";
  };

  # enp2s0 is usually unplugged (no carrier) but defaults to
  # RequiredForOnline, which made systemd-networkd-wait-online block for its
  # full 120s timeout on every boot/switch and report the deploy as failed.
  # --any returns success as soon as the primary enp3s0 is routable.
  systemd.network.wait-online.anyInterface = true;

  # ── Nebula ──────────────────────────────────────────────────────
  # Keep the same Nebula IP as TrueNAS (10.10.0.3) for drop-in replacement.
  # Certs must be deployed to /etc/nebula/{ca.crt,host.crt,host.key}
  # before enabling. Reuse the existing TrueNAS certs from nebula/pki/.
  # (enable + client defaults live in modules/nebula-client.nix)

  # ── Beszel monitoring agent ────────────────────────────────────
  # Report the btrfs RAID1 storage pool in addition to the root fs.
  # (enabled by default in modules/beszel-agent.nix)
  services.beszel-agent.extraFilesystems = [ "/pool" ];

  # ── Pool directory structure ─────────────────────────────────────
  # Ensure subdirectories exist in each btrfs subvolume.
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
    smartmontools # SMART disk health monitoring
    hdparm # disk power management
    rsync
    tree
    pciutils
    usbutils
  ];

  # ── SMART monitoring ─────────────────────────────────────────────
  services.smartd = {
    enable = true;
    autodetect = true;
    notifications = {
      mail.enable = false; # TODO: enable with ntfy or email
      test = true;
    };
  };

  # ── SSH hardening (NAS holds all the data) ──────────────────────
  services.openssh.settings = {
    PasswordAuthentication = lib.mkForce false; # Key-only
  };

  # ── Monitoring ──────────────────────────────────────────────────
  homelab.freshnessChecks = {
    # SMART health of the 4× HDD pool + the NVMe root. smartd still does the
    # background attribute monitoring/logging; this is the alerting layer.
    nas-disks = {
      description = "nas disk SMART health";
      extraPath = [ pkgs.smartmontools ];
      checkCommand = ''
        fail=""
        for d in /dev/sd[a-z] /dev/nvme[0-9]n[0-9]; do
          [ -b "$d" ] || continue
          out="$(smartctl -H "$d" 2>/dev/null)"
          if echo "$out" | grep -qi "overall-health"; then
            echo "$out" | grep -qi "PASSED" || fail="$fail $d"
          fi
        done
        [ -z "$fail" ] || { echo "SMART not PASSED:$fail"; exit 1; }
        echo "all SMART disks PASSED"
      '';
    };
    # The pool holds everything; alert before it fills.
    nas-pool-space = {
      description = "nas /pool free space";
      checkCommand = ''
        p=$(df -P /pool 2>/dev/null | awk 'NR==2{print $5+0}')
        [ -n "$p" ] || { echo "df /pool failed"; exit 1; }
        echo "/pool ''${p}% full"
        [ "$p" -lt 90 ]
      '';
    };
  };

  # ── State version ───────────────────────────────────────────────
  system.stateVersion = "25.11";
}

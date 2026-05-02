# ── Elitedesk 800 G3 Shared Hardware Module ─────────────────────────
#
# All k1-k4 machines are HP EliteDesk 800 G3 with:
#   - Intel CPU (6 cores, VT-x)
#   - 16 GB RAM
#   - 238.5G NVMe (/dev/nvme0n1)
#   - 1.8T HDD (/dev/sda)
#   - Intel I219-LM NIC (eno1) with e1000e driver quirks
#
# This module handles:
#   - Common hardware detection (kvm-intel, xhci_pci, ahci, nvme)
#   - e1000e NIC stability fixes (HW unit hang workaround)
#   - Network buffer tuning
#   - Hardware watchdog
#   - Standard disk layout via disko

{ config, lib, pkgs, ... }:

{
  imports = [
    ./elitedesk-hardware-quirks.nix
  ];

  # ── Firmware / CPU ───────────────────────────────────────────────
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.enableRedistributableFirmware = true;

  # ── Boot ─────────────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "sd_mod" ];
  boot.initrd.kernelModules = [ "dm-snapshot" ];
  boot.kernelModules = [ "kvm-intel" ];

  # ── Zram swap (supplement physical RAM) ─────────────────────────
  zramSwap.enable = true;

  # ── Standard Elitedesk disk layout ───────────────────────────────
  # Applied via disko. Override in host config if needed.
  # Layout: 1G EFI + 16G swap + btrfs root on NVMe; ext4 /mnt/data on HDD
  #
  # NOTE: To apply disk layout during install:
  #   nixos-anywhere --flake .#k1 root@<ip>
  # The disk-config.nix in each host directory selects this layout.

  # ── Platform ─────────────────────────────────────────────────────
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}

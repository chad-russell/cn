{ config, pkgs, ... }:

{
  imports = [
    ../modules/niri-desktop.nix
    ../modules/flatpak.nix
    ../modules/containers.nix
    ../modules/networking.nix
    ../modules/user.nix
    ../modules/base-desktop.nix
  ];

  # Set hostname
  networking.hostName = "bee";

  # Static IP for bee
  customNetworking.staticIP = "192.168.20.105";

  # Use the systemd-boot EFI boot loader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use the latest kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Enable zram swap
  zramSwap.enable = true;

  # Required by NixOS
  system.stateVersion = "25.05";
}


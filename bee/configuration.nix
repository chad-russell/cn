{ config, pkgs, ... }:

{
  imports = [
    ../modules/niri-desktop.nix
    ../modules/flatpak.nix
    ../modules/containers.nix
    ../modules/user.nix
    ../modules/base-desktop.nix
  ];

  # Set hostname
  networking.hostName = "bee";

  # Networking - systemd-networkd with static IP
  systemd.network.enable = true;
  networking.useNetworkd = true;
  networking.useDHCP = false;
  systemd.network.wait-online.enable = false;
  
  systemd.network.networks."10-lan" = {
    matchConfig.Name = "en*";
    networkConfig.DHCP = "no";
    address = [ "192.168.20.105/24" ];
    routes = [ { Gateway = "192.168.20.1"; } ];
    dns = [ "8.8.8.8" "1.1.1.1" ];
  };

  # Enable Tailscale
  services.tailscale.enable = true;
  # To connect to Tailscale, run: sudo tailscale up
  # You'll get a URL to authenticate with your Tailscale account

  # SSH
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "prohibit-password";

  # Use the systemd-boot EFI boot loader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use the latest kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Enable zram swap
  zramSwap.enable = true;

  # Increase Nix download buffer size to 256 MiB (default is 64 MiB)
  nix.settings.download-buffer-size = 268435456;  # 256 MiB

  # Required by NixOS
  system.stateVersion = "25.05";
}


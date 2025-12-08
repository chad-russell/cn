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
  networking.hostName = "think";

  # Use DHCP for think (or set to "192.168.20.XXX" for static IP)
  customNetworking.staticIP = null;

  # Use the systemd-boot EFI boot loader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use the latest kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Enable zram swap (good for laptops - no disk writes)
  zramSwap.enable = true;
  zramSwap.memoryPercent = 50; # Use up to 50% of RAM for compressed swap

  # SSD optimizations
  services.fstrim.enable = true; # Weekly TRIM for SSD health

  # Use tmpfs for /tmp to reduce disk writes and improve performance
  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "16G"; # 50% of 32GB RAM - plenty for temporary operations

  # Laptop power management with TLP
  services.tlp = {
    enable = true;
    settings = {
      # Battery care - limit charge to 80% for longevity (ThinkPad specific)
      START_CHARGE_THRESH_BAT0 = 40;
      STOP_CHARGE_THRESH_BAT0 = 80;
      
      # CPU performance/power balance
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      
      # Enable aggressive power saving on battery
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      CPU_ENERGY_PERF_POLICY_ON_AC = "balance_performance";
      
      # Disable turbo boost on battery for better battery life
      CPU_BOOST_ON_BAT = 0;
      CPU_BOOST_ON_AC = 1;
    };
  };

  # Intel CPU thermal management
  services.thermald.enable = true;

  # Enable Bluetooth
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = false; # Don't enable by default to save power

  # Hardware video acceleration
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # For newer Intel GPUs (Broadwell+)
      intel-vaapi-driver # For older Intel GPUs
      libvdpau-va-gl
    ];
  };

  # Firmware updates
  services.fwupd.enable = true;

  # Required by NixOS
  system.stateVersion = "25.05";
}


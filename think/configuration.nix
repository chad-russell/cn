{ config, pkgs, dms, niri, ... }:

{
  imports = [
    dms.nixosModules.dankMaterialShell
    niri.nixosModules.niri
    ../modules/niri-desktop.nix
    ../modules/gnome-desktop.nix
    ../modules/flatpak.nix
    ../modules/containers.nix
    ../modules/user.nix
    ../modules/base-desktop.nix
  ];

  # Set hostname
  networking.hostName = "think";

  # Networking - NetworkManager for laptop (WiFi support)
  networking.networkmanager.enable = true;
  networking.useDHCP = false;
  
  # SSH
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "prohibit-password";

  # Enable Tailscale
  services.tailscale.enable = true;
  # To connect to Tailscale, run: sudo tailscale up
  # You'll get a URL to authenticate with your Tailscale account

  # Use the systemd-boot EFI boot loader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Nix settings
  nix.settings = {
    trusted-users = [ "root" "crussell" ];
    substituters = [
      "https://cache.nixos.org"
      "https://numtide.cachix.org"
      "https://niri.cachix.org"
    ];
    trusted-public-keys = [
      "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
      "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
    ];
  };

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

  # Power management services for battery monitoring (required by DMS)
  # Note: only upower is needed; power-profiles-daemon conflicts with TLP
  services.upower.enable = true;

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

  # Increase Nix download buffer size to 256 MiB (default is 64 MiB)
  nix.settings.download-buffer-size = 268435456;  # 256 MiB

  # Required by NixOS
  system.stateVersion = "25.05";
}


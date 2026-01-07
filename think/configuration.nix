{
  config,
  pkgs,
  dms,
  niri,
  mango,
  ...
}:

{
  imports = [
    dms.nixosModules.dank-material-shell
    niri.nixosModules.niri
    ../modules/niri-desktop.nix
    ../modules/gnome-desktop.nix
    ../modules/mango-desktop.nix
    ../modules/flatpak.nix
    ../modules/containers.nix
    ../modules/k3s.nix
    ../modules/user.nix
    ../modules/base-desktop.nix
  ];

  # Set hostname
  networking.hostName = "think";

  # Networking - NetworkManager for laptop (WiFi support)
  networking.networkmanager.enable = true;
  networking.useDHCP = false;
  networking.firewall.enable = false;

  # Enable Tailscale
  services.tailscale.enable = true;
  # To connect to Tailscale, run: sudo tailscale up
  # You'll get a URL to authenticate with your Tailscale account

  # Use the systemd-boot EFI boot loader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 6; # Keep only last 6 generations

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

  # Enable printing with CUPS
  services.printing.enable = true;
  services.printing.drivers = with pkgs; [
    gutenprint      # Wide range of printer drivers
    hplip           # HP printers
    brlaser         # Brother laser printers
    brgenml1lpr     # Brother generic drivers
    cnijfilter2     # Canon printers
  ];

  # Enable printer discovery on the network
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

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
  nix.settings.download-buffer-size = 268435456; # 256 MiB

  # Required by NixOS
  system.stateVersion = "25.05";
}

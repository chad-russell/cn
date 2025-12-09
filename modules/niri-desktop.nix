{ config, pkgs, pkgsUnstable, ... }:

{
  # Enable niri compositor
  programs.niri.enable = true;

  # GDM display manager
  services.displayManager.gdm.enable = true;
  services.displayManager.gdm.wayland = true;
  
  # Enable xserver as it's often required for display manager initialization
  # even if we are only running Wayland sessions
  services.xserver.enable = true;
  # Disable X11 desktop manager since we are using niri
  services.desktopManager.gnome.enable = false;

  # XDG portal for proper Wayland integration
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gnome ];

  # Essential desktop packages
  environment.systemPackages = with pkgs; [
    alacritty          # terminal
    fuzzel             # app launcher
    mako               # notifications
    wl-clipboard       # clipboard
    waybar             # status bar (optional but recommended)
    xwayland-satellite # X11 compatibility for niri
    pkgsUnstable.dgop  # dgop from nixpkgs-unstable
    bibata-cursors     # modern cursor theme
  ];

  # Enable hardware graphics support (required for Wayland compositors)
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # For 32-bit apps (Steam, Wine, etc.)
  };

  # Ensure firmware is available for GPU
  hardware.enableRedistributableFirmware = true;

  # Set environment variables for Niri session
  environment.sessionVariables = {
    NIRI_CONFIG = "/home/crussell/.config/niri/config.kdl"; # Explicit config path
    WLR_RENDERER = "vulkan"; # Force Vulkan renderer for better AMD support
    XCURSOR_THEME = "Bibata-Modern-Classic"; # Cursor theme name
    XCURSOR_SIZE = "24"; # Cursor size
  };
}


{ config, pkgs, dms, niri, ... }:

{
  # Enable niri compositor
  programs.niri.enable = true;
  programs.niri.package = niri.packages.${pkgs.system}.niri-unstable;

  # GDM display manager
  services.displayManager.gdm.enable = true;
  services.displayManager.gdm.wayland = true;
  
  # Set Niri as the default session
  services.displayManager.defaultSession = "niri";
  
  # Enable xserver as it's often required for display manager initialization
  # even if we are only running Wayland sessions
  services.xserver.enable = true;

  # Note: XDG portal configuration is now handled by gnome-desktop.nix
  # to avoid conflicts between Niri and GNOME portals

  # Essential desktop packages
  environment.systemPackages = with pkgs; [
    alacritty          # terminal
    fuzzel             # app launcher
    wl-clipboard       # clipboard
    waybar             # status bar (optional but recommended)
    xwayland-satellite # X11 compatibility for niri
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
    XCURSOR_SIZE = "18"; # Cursor size
    GTK_CURSOR_THEME_NAME = "Bibata-Modern-Classic"; # GTK cursor theme
  };
}

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.desktop.niri;
in {
  options.desktop.niri = {
    enable = mkEnableOption "Niri tiling Wayland compositor with GDM";
  };

  config = mkIf cfg.enable {
    # Enable niri compositor
    programs.niri.enable = true;

    # GDM display manager
    services.xserver.displayManager.gdm.enable = true;
    services.xserver.displayManager.gdm.wayland = true;
    
    # Enable xserver as it's often required for display manager initialization
    # even if we are only running Wayland sessions
    services.xserver.enable = true;
    # Disable X11 desktop manager since we are using niri
    services.xserver.desktopManager.gnome.enable = false;

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
    ];
  };
}


{ config, pkgs, ... }:

{
  # Enable GNOME Desktop Environment
  services.desktopManager.gnome.enable = true;

  # Disable power-profiles-daemon (conflicts with TLP in think/configuration.nix)
  services.power-profiles-daemon.enable = false;

  # XDG portal for proper Wayland integration (screen sharing)
  xdg.portal = {
    enable = true;
    extraPortals = [ 
      pkgs.xdg-desktop-portal-gnome
      pkgs.xdg-desktop-portal-gtk
    ];
    # Configure portal backends
    config = {
      common = {
        default = [ "gtk" ];
      };
      gnome = {
        default = [ "gnome" "gtk" ];
        "org.freedesktop.impl.portal.ScreenCast" = [ "gnome" ];
        "org.freedesktop.impl.portal.Screenshot" = [ "gnome" ];
      };
      niri = {
        default = [ "gnome" "gtk" ];
        "org.freedesktop.impl.portal.ScreenCast" = [ "gnome" ];
        "org.freedesktop.impl.portal.Screenshot" = [ "gnome" ];
      };
    };
  };

  # Enable Pipewire for modern audio/video handling (required for screen sharing)
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Essential GNOME applications
  environment.systemPackages = with pkgs; [
    gnome-tweaks           # Advanced GNOME settings
    gnomeExtensions.appindicator  # Tray icons support
    gnome-terminal         # GNOME terminal (in case needed)
    dconf-editor           # Low-level GNOME settings editor
  ];

  # GNOME services
  services.gnome = {
    gnome-keyring.enable = true;
    gnome-browser-connector.enable = true;
  };

  # Exclude unwanted GNOME apps (keep it minimal)
  environment.gnome.excludePackages = with pkgs; [
    gnome-tour             # Welcome tour
    epiphany               # Web browser (use Zen instead)
    geary                  # Email client
    gnome-music            # Music player
    gnome-photos           # Photos app
    totem                  # Video player
    gnome-maps             # Maps
    gnome-weather          # Weather
    gnome-contacts         # Contacts
    gnome-clocks           # Clocks
    simple-scan            # Scanner
    yelp                   # Help viewer
    
    # GNOME Games
    gnome-chess
    gnome-mahjongg
    gnome-mines
    gnome-sudoku
    gnome-tetravex
    hitori
    iagno
    tali
    quadrapassel
    swell-foop
    atomix
    lightsoff
    five-or-more
    four-in-a-row
  ];
}


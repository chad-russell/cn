{ config, pkgs, mango, ... }:

{
  imports = [
    mango.nixosModules.mango
  ];

  # Enable MangoWC compositor
  programs.mango.enable = true;

  # Essential Wayland packages for MangoWC
  environment.systemPackages = with pkgs; [
    mako               # notifications
    wl-clipboard       # clipboard
    bibata-cursors     # modern cursor theme
  ];

  # Set environment variables for MangoWC session
  environment.sessionVariables = {
    XCURSOR_THEME = "Bibata-Modern-Classic";
    XCURSOR_SIZE = "18";
    GTK_CURSOR_THEME_NAME = "Bibata-Modern-Classic";
  };
}



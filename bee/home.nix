{ config, pkgs, dms, quickshell, ... }:

{
  imports = [
    dms.homeModules.dankMaterialShell.default
    quickshell.homeModules.default
  ];

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "crussell";
  home.homeDirectory = "/home/crussell";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "24.11"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [
    # Packages for your Niri/DMS setup
    pkgs.nerdfonts
    pkgs.noto-fonts
    pkgs.noto-fonts-emoji
    pkgs.font-awesome
  ];

  # Niri Configuration
  # We use your existing config.kdl directly
  xdg.configFile."niri/config.kdl".source = ./current-niri-config.kdl;

  # Dank Material Shell
  # See https://github.com/AvengeMedia/DankMaterialShell for configuration options
  # You might need to adjust settings here if DMS needs specific config
  # For now, we just import the module which installs the package.

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}


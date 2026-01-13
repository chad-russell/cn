{
  config,
  pkgs,
  dms,
  ...
}:

{
  imports = [
    ../modules/wezterm
    ../modules/vicinae
    ../modules/oh-my-posh
    ../modules/nixvim
    ../modules/mango
    ../modules/base-desktop-home.nix
    dms.homeModules.dank-material-shell
    dms.homeModules.niri
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
}


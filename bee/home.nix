{ config, pkgs, dms, ... }:

{
  imports = [
    ../modules/wezterm
    ../modules/vicinae
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
    # Dank Material Shell (install as package for now)
    dms.packages.${pkgs.stdenv.hostPlatform.system}.default
    
    # Quickshell - required by DMS
    pkgs.quickshell
    
    # Packages for your Niri/DMS setup
    pkgs.nerd-fonts.fira-code
    pkgs.noto-fonts
    pkgs.noto-fonts-color-emoji
    pkgs.font-awesome

    pkgs.bazaar
    pkgs.distrobox
  ];

  # Niri Configuration
  # We use your existing config.kdl directly
  xdg.configFile."niri/config.kdl" = {
    source = ./current-niri-config.kdl;
    force = true; # Overwrite existing file
  };

  home.enableNixpkgsReleaseCheck = false;

  # Create desktop entry for Bazaar
  xdg.desktopEntries.bazaar = {
    name = "Bazaar";
    genericName = "App Store";
    comment = "Install and manage Flatpak applications";
    exec = "bazaar";
    icon = "bazaar";
    terminal = false;
    categories = [ "System" "PackageManager" ];
  };

  # Wezterm terminal
  programs.weztermModule.enable = true;

  # Zsh shell
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    
    shellAliases = {
      ll = "ls -la";
      update = "sudo nixos-rebuild switch --flake /home/crussell/Code/cn#bee";
    };
    
    history = {
      size = 10000;
      path = "${config.xdg.dataHome}/zsh/history";
    };

    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "docker" "kubectl" ];
      theme = "robbyrussell";
    };
  };

  # Vicinae workspace switcher
  services.vicinaeModule = {
    enable = true;
    autoStart = true;
    settings = {
      font.size = 11;
      theme.name = "vicinae-dark";
      window = {
        csd = true;
        opacity = 0.95;
        rounding = 10;
      };
    };
  };

  # Dank Material Shell
  # See https://github.com/AvengeMedia/DankMaterialShell for configuration options
  # You might need to adjust settings here if DMS needs specific config
  # For now, we just import the module which installs the package.

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}


{ config, pkgs, dms, opencode, ... }:

{
  imports = [
    ../modules/wezterm
    ../modules/vicinae
    ../modules/oh-my-posh
    ../modules/neovim
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

    pkgs.rsync
    pkgs.pgcli

    opencode.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  # Niri Configuration
  # We use your existing config.kdl directly
  xdg.configFile."niri/config.kdl" = {
    source = ./current-niri-config.kdl;
    force = true; # Overwrite existing file
  };

  home.enableNixpkgsReleaseCheck = false;

  # Zsh shell
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    defaultKeymap = "viins";
    
    shellAliases = {
      e = "${pkgs.eza}/bin/eza";
      el = "${pkgs.eza}/bin/eza -alF";
      v = "${pkgs.neovim}/bin/nvim";
      vi = "${pkgs.neovim}/bin/nvim";
      nrs = "sudo nixos-rebuild switch --flake /home/crussell/Code/cn#think";
    };
    
    history = {
      expireDuplicatesFirst = true;
      extended = true;
      size = 50000;
      save = 50000;
      path = "${config.xdg.dataHome}/zsh/history";
    };

    initContent = ''
      function mkcd {
        mkdir $1;
        cd $1;
      }

      function killport {
        lsof -ti:$1 | xargs kill -9
      }

      function whichport {
        lsof -i :$1
      }

      # Keybindings
      # Ctrl+F: accept autosuggestion
      bindkey '^F' autosuggest-accept
      # Ctrl+P: previous line (like up arrow)
      bindkey '^P' up-line-or-history
      # Ctrl+N: next line (like down arrow)
      bindkey '^N' down-line-or-history
    '';
  };

  home.sessionPath = [ "/home/crussell/.local/bin" ];

  # Session environment variables (available in shell sessions)
  home.sessionVariables = {
    XCURSOR_THEME = "Bibata-Modern-Classic";
    XCURSOR_SIZE = "24";
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  # Dank Material Shell
  # See https://github.com/AvengeMedia/DankMaterialShell for configuration options
  # You might need to adjust settings here if DMS needs specific config
  # For now, we just import the module which installs the package.

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}


{
  config,
  pkgs,
  lib,
  noctalia-shell,
  vicinae,
  agenix,
  ...
}:
let
  username = "crussell";
in
{
  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "25.11";

  # Let home-manager manage itself
  programs.home-manager.enable = true;

  # -- Zen Browser (nix flake, replaces flatpak) --
  programs.zen-browser = {
    enable = true;
    setAsDefaultBrowser = true;
  };

  # -- Module imports --
  imports = [
    noctalia-shell.homeModules.default
    ./nvim
    ./zsh.nix
    ./gtk.nix
  ];

  # -- Vicinae launcher --
  services.vicinae = {
    enable = true;
    systemd = {
      enable = true;
      autoStart = true;
      environment = {
        USE_LAYER_SHELL = 1;
      };
    };
    settings = {
      close_on_focus_loss = true;
      pop_to_root_on_close = true;
      font = {
        normal = {
          size = 12;
          family = "JetBrainsMono Nerd Font";
        };
      };
      theme = {
        light.name = "vicinae-light";
        dark.name = "vicinae-dark";
      };
      launcher_window = {
        opacity = 0.98;
      };
    };
  };

  programs.noctalia-shell = {
    enable = true;
    package = noctalia-shell.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };

  # -- Niri config --
  xdg.configFile."niri/config.kdl".source = ./configs/niri/config.kdl;

  # -- Oh My Posh config --
  xdg.configFile."oh-my-posh/config.json".source = ./configs/oh-my-posh/config.json;

  # -- Ghostty config --
  xdg.configFile."ghostty/config".source = ./configs/ghostty/config;

  # Default browser & MIME associations
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "app.zen_browser.zen.desktop";
      "x-scheme-handler/http" = "app.zen_browser.zen.desktop";
      "x-scheme-handler/https" = "app.zen_browser.zen.desktop";
      "x-scheme-handler/about" = "app.zen_browser.zen.desktop";
      "x-scheme-handler/unknown" = "app.zen_browser.zen.desktop";
    };
  };

  # -- Basic CLI / dev tools --
  home.packages = with pkgs; [
    ripgrep
    fd
    bat
    eza
    fzf
    git
    curl
    wget
    zed-editor-fhs
    zoxide
    jq
    oh-my-posh
    github-cli
    yazi

    # GUI apps
    slack
    vesktop
    voxtype

    # Node (needed by `pi install` for extension deps)
    nodejs

    # TUI apps
    slk
  ];

  # -- Git --
  programs.git = {
    enable = true;
    settings.user.name = "Chad Russell";
    settings.user.email = "chaddouglasrussell@gmail.com";
  };

  # -- Agenix secrets --
  age.secrets.zhipu-api-key = {
    file = ./secrets/zhipu-api-key.age;
  };
  age.secrets.openrouter-api-key = {
    file = ./secrets/openrouter-api-key.age;
  };

  # TODO: Package slk (pkgs/slk/package.nix) for nixpkgs upstream PR
  # Tell agenix where to find the decryption key
  age.identityPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];

  # -- Voxtype voice-to-text daemon --
  systemd.user.services.voxtype = {
    Unit = {
      Description = "Voxtype push-to-talk voice-to-text daemon";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" "pipewire.service" "pipewire-pulse.service" ];
    };

    Service = {
      Type = "simple";
      ExecStart = "${pkgs.voxtype}/bin/voxtype -q daemon";
      Restart = "on-failure";
      RestartSec = 5;
    };

    Install.WantedBy = [ "graphical-session.target" ];
  };

  # -- Bash (kept as fallback shell) --
  programs.bash = {
    enable = true;
    enableCompletion = true;
    shellAliases = {
      ll = "eza -l --icons";
      la = "eza -la --icons";
    };
  };
}

{
  config,
  pkgs,
  llm-agents,
  opencode,
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

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [
    pkgs.nerd-fonts.fira-code
    pkgs.noto-fonts
    pkgs.noto-fonts-color-emoji
    pkgs.font-awesome

    pkgs.bazaar
    pkgs.distrobox

    pkgs.rsync
    pkgs.pgcli
    pkgs.ripgrep
    pkgs.bat
    pkgs.jq
    pkgs.terraform
    pkgs.awscli2
    pkgs.yazi
    pkgs.just

    opencode.packages.${pkgs.stdenv.hostPlatform.system}.default

    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.gemini-cli
    llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex
  ];

  # Dank Material Shell with niri and mango integration
  programs.dank-material-shell = {
    enable = true;
    systemd = {
      enable = true;
      restartIfChanged = true;
    };
    enableSystemMonitoring = false; # Disable to avoid dgop dependency issue
    enableDynamicTheming = true;
    niri = {
      enableKeybinds = false;
      enableSpawn = false; # Use systemd service instead to avoid double spawn
    };
    # DMS should also work with mango - keybinds are configured in mango config
  };

  # Niri keybinds (via niri home module) to match your existing config
  programs.niri.settings.binds = {
    # Alt-Tab switcher (new in v25.11)
    # "Mod+Tab".action.switch-focus-between-windows = [ ];
    # "Mod+Shift+Tab".action.switch-focus-between-windows = [ ];

    # Window/column navigation
    "Mod+Left".action.focus-column-left = [ ];
    "Mod+Down".action.focus-window-down = [ ];
    "Mod+Up".action.focus-window-up = [ ];
    "Mod+Right".action.focus-column-right = [ ];
    "Mod+H".action.focus-column-left = [ ];
    "Mod+J".action.focus-window-down = [ ];
    "Mod+K".action.focus-window-up = [ ];
    "Mod+L".action.focus-column-right = [ ];
    "Mod+O".action.toggle-overview = [ ];

    # Window/column movement
    "Mod+Ctrl+Left".action.move-column-left = [ ];
    "Mod+Ctrl+Right".action.move-column-right = [ ];
    "Mod+Ctrl+H".action.move-column-left = [ ];
    "Mod+Ctrl+L".action.move-column-right = [ ];
    "Mod+BracketLeft".action.consume-or-expel-window-left = [ ];
    "Mod+BracketRight".action.consume-or-expel-window-right = [ ];
    "Mod+Ctrl+Down".action.move-column-to-workspace-down = [ ];
    "Mod+Ctrl+J".action.move-column-to-workspace-down = [ ];
    "Mod+Ctrl+Up".action.move-column-to-workspace-up = [ ];
    "Mod+Ctrl+K".action.move-column-to-workspace-up = [ ];

    # Window sizing
    "Mod+Minus".action.set-column-width = [ "-10%" ];
    "Mod+Equal".action.set-column-width = [ "+10%" ];
    "Mod+Shift+Minus".action.set-window-height = [ "-10%" ];
    "Mod+Shift+Equal".action.set-window-height = [ "+10%" ];

    # Window actions
    "Mod+P".action.screenshot = [ ];
    "Mod+V".action.toggle-window-floating = [ ];
    "Mod+Shift+V".action.switch-focus-between-floating-and-tiling = [ ];
    "Mod+Q".action.close-window = [ ];
    "Mod+X".action.maximize-column = [ ];
    "Mod+Shift+F".action.fullscreen-window = [ ];

    # Workspace switcher (vicinae)
    "Mod+Space".action.spawn = [
      "${pkgs.vicinae}/bin/vicinae"
      "toggle"
    ];

    # Monitor navigation
    "Mod+Shift+Left".action.focus-monitor-left = [ ];
    "Mod+Shift+H".action.focus-monitor-left = [ ];
    "Mod+Shift+Down".action.focus-monitor-down = [ ];
    "Mod+Shift+J".action.focus-workspace-down = [ ];
    "Mod+Shift+Up".action.focus-monitor-up = [ ];
    "Mod+Shift+K".action.focus-workspace-up = [ ];
    "Mod+Shift+Right".action.focus-monitor-right = [ ];
    "Mod+Shift+L".action.focus-monitor-right = [ ];

    # Move to monitor
    "Mod+Shift+Ctrl+Left".action.move-column-to-monitor-left = [ ];
    "Mod+Shift+Ctrl+Down".action.move-column-to-monitor-down = [ ];
    "Mod+Shift+Ctrl+Up".action.move-column-to-monitor-up = [ ];
    "Mod+Shift+Ctrl+Right".action.move-column-to-monitor-right = [ ];
    "Mod+Shift+Ctrl+H".action.move-column-to-monitor-left = [ ];
    "Mod+Shift+Ctrl+J".action.move-column-to-monitor-down = [ ];
    "Mod+Shift+Ctrl+K".action.move-column-to-monitor-up = [ ];
    "Mod+Shift+Ctrl+L".action.move-column-to-monitor-right = [ ];

    # DMS keybinds (manually configured to avoid conflicts)
    "Mod+N".action.spawn = [
      "dms"
      "ipc"
      "notifications"
      "toggle"
    ];
    "Mod+Comma".action.spawn = [
      "dms"
      "ipc"
      "settings"
      "toggle"
    ];
    "Super+Alt+L".action.spawn = [
      "dms"
      "ipc"
      "lock"
      "lock"
    ];
    "Mod+M".action.spawn = [
      "dms"
      "ipc"
      "processlist"
      "toggle"
    ];
    "Mod+Alt+N" = {
      allow-when-locked = true;
      action.spawn = [
        "dms"
        "ipc"
        "night"
        "toggle"
      ];
    };
    "Mod+E".action.spawn = [
      "dms"
      "ipc"
      "powermenu"
      "toggle"
    ];

    # Applications
    "Mod+T".action.spawn = [ "wezterm" ];
    "Mod+B".action.spawn = [
      "flatpak"
      "run"
      "app.zen_browser.zen"
    ];
    "Mod+F".action.spawn = [
      "nautilus"
      "--new-window"
    ];

    # Media keys (DMS)
    "XF86AudioRaiseVolume" = {
      allow-when-locked = true;
      action.spawn = [
        "dms"
        "ipc"
        "audio"
        "increment"
        "3"
      ];
    };
    "XF86AudioLowerVolume" = {
      allow-when-locked = true;
      action.spawn = [
        "dms"
        "ipc"
        "audio"
        "decrement"
        "3"
      ];
    };
    "XF86AudioMute" = {
      allow-when-locked = true;
      action.spawn = [
        "dms"
        "ipc"
        "audio"
        "mute"
      ];
    };
    "XF86AudioMicMute" = {
      allow-when-locked = true;
      action.spawn = [
        "dms"
        "ipc"
        "audio"
        "micmute"
      ];
    };
    "XF86MonBrightnessUp" = {
      allow-when-locked = true;
      action.spawn = [
        "dms"
        "ipc"
        "brightness"
        "increment"
        "5"
        ""
      ];
    };
    "XF86MonBrightnessDown" = {
      allow-when-locked = true;
      action.spawn = [
        "dms"
        "ipc"
        "brightness"
        "decrement"
        "5"
        ""
      ];
    };
  };

  programs.niri.settings.window-rules = [
    # Blanket rule: rounded corners for all windows
    {
      geometry-corner-radius = {
        top-left = 12.0;
        top-right = 12.0;
        bottom-left = 12.0;
        bottom-right = 12.0;
      };
      clip-to-geometry = true;
    }

    # Firefox Picture-in-Picture and Zoom floating
    {
      matches = [
        {
          app-id = "^firefox$";
          title = "^Picture-in-Picture$";
        }
      ];
      open-floating = true;
    }
  ];

  programs.niri.settings.gestures.hot-corners.enable = false;

  programs.niri.settings.layout.focus-ring.width = 2;
  programs.niri.settings.layout.gaps = 8;

  programs.niri.settings.input = {
    keyboard = {
      xkb.layout = "us";
      xkb.options = "caps:swapescape";
      numlock = true;
    };
    touchpad = {
      tap = true;
      natural-scroll = true;
      scroll-factor = 0.18;
    };
  };

  programs.niri.settings.spawn-at-startup = [
    { command = [ "${pkgs.xwayland-satellite}/bin/xwayland-satellite" ]; }
  ];

  programs.niri.settings.prefer-no-csd = true;
  programs.niri.settings.screenshot-path = "~/Pictures/Screenshots/%Y-%m-%d %H-%M-%S.png";
  programs.niri.settings.hotkey-overlay.skip-at-startup = true;

  programs.niri.settings.cursor = {
    theme = "Bibata-Modern-Classic";
    size = 18;
  };

  # Monitor configuration
  programs.niri.settings.outputs = {
    # Laptop Screen (AU Optronics) - Scaled at 1.25 for better readability
    "eDP-1" = {
      mode = {
        width = 1920;
        height = 1200;
        refresh = 60.0;
      };
      scale = 1.25;
      position = {
        x = 0;
        y = 0;
      };
    };
    # First Dell Monitor
    "DP-3" = {
      mode = {
        width = 1920;
        height = 1080;
        refresh = 60.0;
      };
      scale = 1.0;
      position = {
        x = 1536;
        y = 0;
      };
    };
    # Second Dell Monitor
    "DP-4" = {
      mode = {
        width = 1920;
        height = 1080;
        refresh = 60.0;
      };
      scale = 1.0;
      position = {
        x = 0;
        y = 0;
      };
    };
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
      v = "nvim";
      vi = "nvim";
      nrs = "sudo nixos-rebuild switch --flake /home/crussell/Code/cn#think";
      hms = "home-manager switch --flake /home/crussell/Code/cn#think";
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

      alias resource_home_env='unset __HM_SESS_VARS_SOURCED && source ~/.zshenv'

      # Keybindings
      # Ctrl+F: accept autosuggestion
      bindkey '^F' autosuggest-accept
      # Ctrl+P: previous line (like up arrow)
      bindkey '^P' up-line-or-history
      # Ctrl+N: next line (like down arrow)
      bindkey '^N' down-line-or-history
    '';
  };

  # Add ~/.local/bin to PATH (for user-installed scripts)
  home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];

  # Session environment variables (available in shell sessions)
  home.sessionVariables = {
    DISPLAY = ":0";
    XCURSOR_THEME = "Bibata-Modern-Classic";
    XCURSOR_SIZE = "18";
    GTK_CURSOR_THEME_NAME = "Bibata-Modern-Classic";
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}

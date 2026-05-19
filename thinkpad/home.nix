{
  config,
  pkgs,
  lib,
  noctalia-shell,
  vicinae,
  agenix,
  hyprland,
  ...
}:
let
  username = "crussell";
  wycliffePortal = "wycliffe.gpcloudservice.com";
  wycliffeVpn = pkgs.writeShellScriptBin "wycliffe-vpn" ''
    set -euo pipefail

    PORTAL="${wycliffePortal}"
    BROWSER="''${WYCLIFFE_VPN_BROWSER:-zen-twilight}"
    GPCLIENT="${pkgs.globalprotect-openconnect}/bin/gpclient"
    SUDO="/run/wrappers/bin/sudo"
    IP="${pkgs.iproute2}/bin/ip"
    GREP="${pkgs.gnugrep}/bin/grep"
    SLEEP="${pkgs.coreutils}/bin/sleep"
    WLPASTE="${pkgs.wl-clipboard}/bin/wl-paste"

    is_connected() {
      "$IP" route | "$GREP" -q '^default dev tun0 scope link'
    }

    feed_callback() {
      local callback="''${1:-}"
      case "$callback" in
        globalprotectcallback:*)
          echo
          echo "Handing browser callback to gpclient..."
          "$GPCLIENT" launch-gui "$callback"
          ;;
        *)
          return 1
          ;;
      esac
    }

    if is_connected; then
      echo "Wycliffe VPN already appears connected."
      exit 0
    fi

    echo "Authenticating sudo..."
    "$SUDO" -v

    initial_clipboard="$($WLPASTE --no-newline 2>/dev/null || true)"
    tty_ok=0
    if [ -r /dev/tty ]; then
      exec 3</dev/tty
      tty_ok=1
    fi

    echo "Starting Wycliffe VPN via browser: $BROWSER"
    "$SUDO" -E "$GPCLIENT" connect "$PORTAL" --browser "$BROWSER" &
    connect_pid=$!

    instructed=0
    while kill -0 "$connect_pid" 2>/dev/null; do
      if [ -f /tmp/gpcallback.port ]; then
        if [ "$instructed" -eq 0 ]; then
          cat <<'EOF'

If the browser login finishes but the VPN does not continue automatically:
  1. In the browser, click "click here" once.
  2. If nothing happens, right-click "click here" and choose "Copy Link".
  3. This script will auto-detect the copied globalprotectcallback link.
  4. Or paste the full globalprotectcallback:... link here and press Enter.

EOF
          instructed=1
        fi

        clipboard="$($WLPASTE --no-newline 2>/dev/null || true)"
        if [ "$clipboard" != "$initial_clipboard" ] && feed_callback "$clipboard"; then
          initial_clipboard="$clipboard"
        fi

        if [ "$tty_ok" -eq 1 ]; then
          if IFS= read -r -t 1 -u 3 line; then
            if feed_callback "$line"; then
              :
            elif [ -n "$line" ]; then
              echo "Ignoring input that does not start with globalprotectcallback:"
            fi
          fi
        else
          "$SLEEP" 1
        fi
      else
        "$SLEEP" 1
      fi
    done

    set +e
    wait "$connect_pid"
    rc=$?
    set -e

    for _ in 1 2 3 4 5; do
      if is_connected; then
        echo "Wycliffe VPN connected."
        exit 0
      fi
      "$SLEEP" 1
    done

    echo "Wycliffe VPN did not come up."
    exit "$rc"
  '';
  wycliffeVpnDisconnect = pkgs.writeShellScriptBin "wycliffe-vpn-disconnect" ''
    set -euo pipefail

    GPCLIENT="${pkgs.globalprotect-openconnect}/bin/gpclient"
    SUDO="/run/wrappers/bin/sudo"
    IP="${pkgs.iproute2}/bin/ip"
    GREP="${pkgs.gnugrep}/bin/grep"
    SLEEP="${pkgs.coreutils}/bin/sleep"

    is_connected() {
      "$IP" route | "$GREP" -q '^default dev tun0 scope link'
    }

    if ! is_connected && ! "$IP" link show tun0 >/dev/null 2>&1; then
      echo "Wycliffe VPN does not appear connected."
      exit 0
    fi

    echo "Disconnecting Wycliffe VPN..."
    "$SUDO" "$GPCLIENT" disconnect

    for _ in 1 2 3 4 5; do
      if ! is_connected && ! "$IP" link show tun0 >/dev/null 2>&1; then
        echo "Wycliffe VPN disconnected."
        exit 0
      fi
      "$SLEEP" 1
    done

    echo "Disconnect requested; tun0 is still present. Check 'ip route' or re-run if needed."
  '';
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
    extraPrefs = ''
      // Exclude dev.crussell.io from DNS-over-HTTPS so split DNS via
      // AdGuardHome on bee (Nebula) is used instead of the DoH resolver.
      pref("network.trr.excluded-domains", "dev.crussell.io");
    '';
  };

  # -- Module imports --
  imports = [
    noctalia-shell.homeModules.default
    ./nvim
    ./zsh.nix
    ./gtk.nix
    ../modules/zellij.nix
    ../modules/zellij.nix
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

  # -- Hyprland config --
  xdg.configFile."hypr/hyprland.lua".source = ./configs/hyprland/hyprland.lua;

  # Lua LSP config — point lua-language-server at Hyprland's autogenerated stubs
  # so the `hl` global and all its fields resolve correctly.
  xdg.configFile."hypr/.luarc.json".text = builtins.toJSON {
    workspace = {
      library = [
        "${hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland}/share/hypr/stubs"
      ];
    };
    diagnostics = {
      globals = [ "hl" ];
    };
  };

  # -- MangoWC (dwm-like Wayland compositor with scroller layout) --
  # Translated from niri config for a consistent experience.
  # Start from TTY: mangowc (wrapper) or mango
  # The HM module generates ~/.config/mango/config.conf with validation
  # and sets up a mango-session.target for systemd integration.
  # Vicinae and noctalia-shell auto-start via their systemd user services
  # (WantedBy graphical-session.target, which mango-session binds to).
  wayland.windowManager.mango = {
    enable = true;
    systemd.enable = true;

    autostart_sh = ''
      xwayland-satellite &
    '';

    settings = {
      # ── Keyboard ──────────────────────────────────────────────────
      xkb_rules_layout = "us";
      xkb_rules_options = "caps:swapescape";

      # ── Touchpad ──────────────────────────────────────────────────
      tap_to_click = 1;
      trackpad_natural_scrolling = 1;
      trackpad_scroll_factor = "0.18";

      # ── Cursor ────────────────────────────────────────────────────
      cursor_theme = "Bibata-Modern-Classic";
      cursor_size = 18;

      # ── Environment ───────────────────────────────────────────────
      env = [
        "XCURSOR_SIZE,18"
        "XCURSOR_THEME,Bibata-Modern-Classic"
      ];

      # ── Appearance ────────────────────────────────────────────────
      gappih = 8;
      gappiv = 8;
      gappoh = 8;
      gappov = 8;
      borderpx = 2;
      border_radius = 12;
      focused_opacity = "1.0";
      unfocused_opacity = "1.0";

      # ── Window effects ────────────────────────────────────────────
      blur = 1;
      blur_optimized = 1;
      shadows = 1;
      shadows_size = 4;

      # ── Animations ────────────────────────────────────────────────
      # Approximating niri's critically-damped spring physics (damping-ratio=1.0)
      # with bezier curves that match the exponential-deceleration profile.
      # Curve 0.16,1,0.3,1 = fast start, smooth settle, no overshoot.
      animations = 1;

      # Slide feels closer to niri's view-movement springs than zoom
      animation_type_open = "slide";
      animation_type_close = "slide";

      # Durations tuned to niri spring settling times:
      #   open/close ≈ stiffness 800 (~500ms settle)
      #   tag switch ≈ stiffness 1000 (~300ms settle)
      animation_duration_open = 500;
      animation_duration_close = 350;
      animation_duration_move = 500;
      animation_duration_tag = 300;

      # Critically-damped spring approximation curves
      animation_curve_open = "0.16,1,0.3,1";
      animation_curve_close = "0.16,1,0.3,1";
      animation_curve_move = "0.16,1,0.3,1";
      animation_curve_tag = "0.16,1,0.3,1";
      animation_curve_focus = "0.16,1,0.3,1";
      animation_curve_opafadein = "0.16,1,0.3,1";
      animation_curve_opafadeout = "0.16,1,0.3,1";

      # ── Focus behavior ────────────────────────────────────────────
      focus_cross_monitor = 1;

      # ── Layout (scroller for all tags, like niri) ─────────────────
      circle_layout = "scroller";
      scroller_default_proportion = "0.9";
      scroller_prefer_overspread = 1;

      # ── Monitor rules ─────────────────────────────────────────────
      # NOTE: Monitor names may differ from niri. Run `wlr-randr` after
      # starting mango and adjust names here if needed.
      monitorrule = [
        "name:^DP-3$,width:3840,height:2160,refresh:60,x:0,y:0,scale:1.25"
        "name:^DP-5$,width:3840,height:2160,refresh:60,x:3072,y:0,scale:1.25"
        "name:^eDP-1$,width:1920,height:1200,refresh:60,x:4224,y:1728,scale:1.0"
      ];

      # ── Tag rules (scroller layout for all tags) ──────────────────
      tagrule = [
        "id:1,layout_name:scroller"
        "id:2,layout_name:scroller"
        "id:3,layout_name:scroller"
        "id:4,layout_name:scroller"
        "id:5,layout_name:scroller"
        "id:6,layout_name:scroller"
        "id:7,layout_name:scroller"
        "id:8,layout_name:scroller"
        "id:9,layout_name:scroller"
      ];

      # ── Window rules ──────────────────────────────────────────────
      windowrule = [
        # Firefox Picture-in-Picture
        "isfloating:1,title:^Picture-in-Picture$"
        # Zoom floating windows
        "isfloating:1,title:.*menu.*"
        "isfloating:1,title:Settings"
        "isfloating:1,title:Audio Settings"
        "isfloating:1,title:.*Sharing.*"
        "isfloating:1,title:Chat"
      ];

      # ── Keybindings ───────────────────────────────────────────────
      bind = [
        # Focus (vim keys + arrows)
        "SUPER,Left,focusdir,left"
        "SUPER,Right,focusdir,right"
        "SUPER,Up,focusdir,up"
        "SUPER,Down,focusdir,down"
        "SUPER,h,focusdir,left"
        "SUPER,j,focusdir,down"
        "SUPER,k,focusdir,up"
        "SUPER,l,focusdir,right"

        # Overview (hycov-style)
        "SUPER,o,toggleoverview"

        # Move windows
        "SUPER+Ctrl,Left,smartmovewin,left"
        "SUPER+Ctrl,Right,smartmovewin,right"
        "SUPER+Ctrl,h,smartmovewin,left"
        "SUPER+Ctrl,l,smartmovewin,right"

        # Scroller: stack/unstack windows (≈ niri consume/expel)
        "SUPER,bracketleft,scroller_stack,left"
        "SUPER,bracketright,scroller_stack,right"

        # Move to adjacent tag (workspace)
        "SUPER+Ctrl,Down,tagtoright,0"
        "SUPER+Ctrl,j,tagtoright,0"
        "SUPER+Ctrl,Up,tagtoleft,0"
        "SUPER+Ctrl,k,tagtoleft,0"

        # Window sizing (scroller proportion presets)
        "SUPER,minus,switch_proportion_preset,prev"
        "SUPER,equal,switch_proportion_preset,next"
        "SUPER+Shift,minus,smartresizewin,up"
        "SUPER+Shift,equal,smartresizewin,down"

        # Window actions
        "SUPER,p,spawn_shell,mkdir -p ~/Pictures/Screenshots && grim -g \"$(slurp)\" ~/Pictures/Screenshots/$(date +%Y-%m-%d_%H-%M-%S).png"
        "SUPER,v,togglefloating"
        "SUPER+Shift,v,focuslast"
        "SUPER,q,killclient"
        "SUPER+Shift,f,togglefullscreen"
        "SUPER,x,togglemaximizescreen"

        # Workspace switcher (vicinae)
        "SUPER,space,spawn,vicinae toggle"

        # Focus monitor
        "SUPER+Shift,Left,focusmon,left"
        "SUPER+Shift,H,focusmon,left"
        "SUPER+Shift,Right,focusmon,right"
        "SUPER+Shift,L,focusmon,right"
        "SUPER+Shift,Down,focusmon,down"
        "SUPER+Shift,Up,focusmon,up"

        # Cycle tags (workspace up/down, like niri)
        "SUPER+Shift,j,viewtoright,0"
        "SUPER+Shift,l,viewtoright,0"
        "SUPER+Shift,k,viewtoleft,0"
        "SUPER+Shift,h,viewtoleft,0"

        # Move to monitor
        "SUPER+Ctrl+Shift,Left,tagmon,left"
        "SUPER+Ctrl+Shift,Right,tagmon,right"
        "SUPER+Ctrl+Shift,H,tagmon,left"
        "SUPER+Ctrl+Shift,L,tagmon,right"
        "SUPER+Ctrl+Shift,Down,tagmon,down"
        "SUPER+Ctrl+Shift,Up,tagmon,up"
        "SUPER+Ctrl+Shift,J,tagmon,down"
        "SUPER+Ctrl+Shift,K,tagmon,up"

        # ── Noctalia keybinds ───────────────────────────────────────
        "SUPER,n,spawn,noctalia-shell ipc call notifications toggleDND"
        "SUPER,comma,spawn,noctalia-shell ipc call settings toggle"
        "SUPER+Alt,l,spawn,noctalia-shell ipc call lockScreen lock"
        "SUPER,m,spawn,noctalia-shell ipc call systemMonitor toggle"
        "SUPER+Alt,n,spawn,noctalia-shell ipc call nightLight toggle"
        "SUPER,e,spawn,noctalia-shell ipc call sessionMenu toggle"

        # ── Applications ────────────────────────────────────────────
        "SUPER,t,spawn,ghostty"
        "SUPER,b,spawn,flatpak run app.zen_browser.zen"
        "SUPER,f,spawn,nautilus --new-window"
        "SUPER,r,spawn,voxtype record toggle"

        # ── Compositor ──────────────────────────────────────────────
        "SUPER+Shift,r,reload_config"

        # ── Numbered tags (1-9) ─────────────────────────────────────
        "SUPER,1,view,1"
        "SUPER,2,view,2"
        "SUPER,3,view,3"
        "SUPER,4,view,4"
        "SUPER,5,view,5"
        "SUPER,6,view,6"
        "SUPER,7,view,7"
        "SUPER,8,view,8"
        "SUPER,9,view,9"
        "SUPER+Shift,1,tag,1,1"
        "SUPER+Shift,2,tag,2,1"
        "SUPER+Shift,3,tag,3,1"
        "SUPER+Shift,4,tag,4,1"
        "SUPER+Shift,5,tag,5,1"
        "SUPER+Shift,6,tag,6,1"
        "SUPER+Shift,7,tag,7,1"
        "SUPER+Shift,8,tag,8,1"
        "SUPER+Shift,9,tag,9,1"
        "SUPER+Ctrl,1,tagsilent,1"
        "SUPER+Ctrl,2,tagsilent,2"
        "SUPER+Ctrl,3,tagsilent,3"
        "SUPER+Ctrl,4,tagsilent,4"
        "SUPER+Ctrl,5,tagsilent,5"
        "SUPER+Ctrl,6,tagsilent,6"
        "SUPER+Ctrl,7,tagsilent,7"
        "SUPER+Ctrl,8,tagsilent,8"
        "SUPER+Ctrl,9,tagsilent,9"
      ];

      # ── Media keys (work when screen is locked) ───────────────────
      bindl = [
        "NONE,XF86AudioRaiseVolume,spawn,noctalia-shell ipc call volume increase"
        "NONE,XF86AudioLowerVolume,spawn,noctalia-shell ipc call volume decrease"
        "NONE,XF86AudioMute,spawn,noctalia-shell ipc call volume muteOutput"
        "NONE,XF86AudioMicMute,spawn,noctalia-shell ipc call volume muteInput"
        "NONE,XF86MonBrightnessUp,spawn,noctalia-shell ipc call brightness increase"
        "NONE,XF86MonBrightnessDown,spawn,noctalia-shell ipc call brightness decrease"
      ];
    };
  };

  # -- Oh My Posh config --
  xdg.configFile."oh-my-posh/config.json".source = ./configs/oh-my-posh/config.json;

  # -- Zellij config --
  xdg.configFile."zellij/config.kdl".source = ./configs/zellij/config.kdl;

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
    bun

    # Hyprland launcher wrapper — sets XDG_CURRENT_DESKTOP and starts
    # start-hyprland so that portals and systemd services work correctly.
    # Usage: from TTY, run `hypr`
    (writeShellScriptBin "hypr" ''
      export XDG_CURRENT_DESKTOP=Hyprland
      export XDG_SESSION_TYPE=wayland
      exec start-hyprland "$@"
    '')

    # Mango compositor wrapper — sets XDG_CURRENT_DESKTOP and starts
    # mango so that portals and systemd services work correctly.
    # Usage: from TTY, run `mangowc`
    (writeShellScriptBin "mangowc" ''
      export XDG_CURRENT_DESKTOP=mango
      export XDG_SESSION_TYPE=wayland
      exec mango "$@"
    '')

    # Window switcher for Hyprland 0.55+ (Lua IPC)
    # Workaround for vicinae's window switching being broken on 0.55.
    (writeShellScriptBin "hl-window-switcher" (builtins.readFile ./scripts/hl-window-switcher))

    # GUI apps
    slack
    vesktop
    voxtype
    localsend
    zoom-us

    # Node (needed by `pi install` for extension deps)
    nodejs

    # TUI apps
    slk

    # VPN helpers
    wycliffeVpn
    wycliffeVpnDisconnect
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

  # -- Gloo SSH tunnel (start/stop manually) --
  # Usage:  systemctl --user start gloo-tunnel
  #         systemctl --user stop gloo-tunnel
  #
  # Forwards all Gloo ports. Polymer and Hummingbird share 3000/3001,
  # so don't run both simultaneously.
  #
  # Ports:
  #   3000  polymer app / hummingbird web
  #   3001  admin360 / hummingbird storyhub
  #   3006  gpl
  #   8000  hummingbird API
  systemd.user.services.gloo-tunnel = {
    Unit.Description = "SSH tunnel: Gloo ports → bee";
    Service = {
      ExecStart = "${pkgs.openssh}/bin/ssh -N -o ExitOnForwardFailure=yes"
        + " -L 3000:127.0.0.1:3000"
        + " -L 3001:127.0.0.1:3001"
        + " -L 3006:127.0.0.1:3006"
        + " -L 8000:127.0.0.1:8000"
        + " bee";
      RestartSec = 5;
    };
  };

  # -- SSH client config (Nebula hosts) --
  programs.ssh = {
    enable = true;
    matchBlocks = {
      bee = {
        hostname = "10.10.0.12";
        identityFile = "~/.ssh/id_ed25519";
        extraOptions.StrictHostKeyChecking = "accept-new";
      };
      bees = {
        hostname = "10.10.0.6";
        identityFile = "~/.ssh/id_ed25519";
        extraOptions.StrictHostKeyChecking = "accept-new";
      };
    };
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

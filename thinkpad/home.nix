{
  config,
  pkgs,
  lib,
  noctalia-shell,
  vicinae,
  agenix,
  unstable,
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
          "$GPCLIENT" launch-gui "$callback";
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
  # zsh + GTK are owned by home-manager again (recovered off the deprecated hod profile).
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

  programs.noctalia = {
    enable = true;
  };

  # ── Dotfiles (recovered off hod; home-manager deploys them now) ─────────
  xdg.configFile."ghostty/config".source = ./configs/ghostty/config;
  xdg.configFile."niri/config.kdl".source = ./configs/niri/config.kdl;
  xdg.configFile."oh-my-posh/config.json".source = ./configs/oh-my-posh/config.json;
  xdg.configFile."zellij/config.kdl".source = ./configs/zellij/config.kdl;
  xdg.configFile."ssh/config".source = ./configs/ssh/config;
  xdg.configFile."mimeapps.list".source = ./configs/mimeapps.list;

  # -- dconf settings (dark theme, cursor, caps-escape, Super modifier) --
  dconf.settings = {
    "org/gnome/desktop/wm/preferences" = {
      mouse-button-modifier = "<Super>";
    };
    "org/gnome/desktop/input-sources" = {
      xkb-options = [ "caps:swapescape" ];
    };
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "Adwaita-dark";
      icon-theme = "Papirus-Dark";
      cursor-theme = "Adwaita";
      cursor-size = 24;
      font-name = "Noto Sans 10";
    };
  };

  # ── Packages (recovered off the deprecated hod profile) ────────────────────
  home.packages = with pkgs; [
    # --- CLI / dev tools ---
    ripgrep
    fd
    bat
    eza
    fzf
    git
    github-cli
    jq
    oh-my-posh
    curl
    wget
    yazi
    zoxide
    file
    htop
    less
    ncdu
    openssh
    pv
    rsync
    strace
    tree
    unzip
    lsof

    # --- Dev runtimes / editors ---
    nodejs
    bun
    lazygit
    tig
    tmux
    vim
    nano
    wl-clipboard
    distrobox
    zed-editor-fhs
    python3
    libvirt

    # --- Toolchains ---
    go
    rustc
    cargo

    # --- Security / encryption ---
    age
    gnupg

    # --- Wayland CLI utilities ---
    brightnessctl
    playerctl

    # --- Terminal (was hod-built) ---
    ghostty

    # --- GTK theme packages ---
    gnome-themes-extra
    papirus-icon-theme
    adwaita-icon-theme

    # --- GUI apps ---
    slack
    vesktop
    voxtype
    localsend
    zoom-us
    bazaar
    gnome-boxes
    warp-terminal

    # --- AI coding assistants ---
    claude-code
    cursor-cli

    # --- VPN helpers ---
    wycliffeVpn
    wycliffeVpnDisconnect
  ];

  # -- Git --
  programs.git = {
    enable = true;
    userName = "Chad Russell";
    userEmail = "chaddouglasrussell@gmail.com";
  };

  # -- Agenix secrets --
  age.secrets.zhipu-api-key = {
    file = ./secrets/zhipu-api-key.age;
  };
  age.secrets.openrouter-api-key = {
    file = ./secrets/openrouter-api-key.age;
  };
  age.identityPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];

  # ── systemd user services (recovered off the hod profile) ────────────

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

  # -- Polymer/Gloo SSH tunnel (start/stop manually) --
  # Usage:  systemctl --user start gloo-tunnel
  #         systemctl --user stop gloo-tunnel
  systemd.user.services.gloo-tunnel = {
    Unit.Description = "SSH tunnel: Gloo ports -> bee";
    Service = {
      ExecStart =
        "${pkgs.openssh}/bin/ssh -N -o ExitOnForwardFailure=yes"
        + " -L 3000:127.0.0.1:3000"
        + " -L 3001:127.0.0.1:3001"
        + " -L 3006:127.0.0.1:3006"
        + " -L 8000:127.0.0.1:8000"
        + " bee";
      RestartSec = 5;
    };
  };

  # -- opencode: managed by the system module (modules/opencode.nix),
  # services.opencode.enable = true in configuration.nix. Run `opencode web` manually.

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

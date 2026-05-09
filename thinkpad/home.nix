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
    bun

    # GUI apps
    slack
    vesktop
    voxtype
    localsend

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

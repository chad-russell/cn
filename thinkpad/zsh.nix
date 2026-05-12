{
  config,
  pkgs,
  lib,
  ...
}:
let
  username = "crussell";
in
{
  programs.zsh = {
    enable = true;

    # Autosuggestions
    autosuggestion.enable = true;

    # Syntax highlighting
    syntaxHighlighting.enable = true;

    # History
    history = {
      path = "${config.xdg.stateHome}/zsh/history";
      size = 100000;
      save = 100000;
      extended = true;
      expireDuplicatesFirst = true;
      ignoreDups = true;
      ignoreSpace = true;
      share = true;
    };

    # Completion
    enableCompletion = true;

    # Default keymap
    defaultKeymap = "viins";

    # Init content (replaces deprecated initExtra)
    initContent = lib.mkBefore ''
      # -- Decrypted secrets (every shell, not gated by session guard) --
      export ZHIPU_API_KEY="$(${pkgs.coreutils}/bin/cat ${config.age.secrets.zhipu-api-key.path})"
      export OPENROUTER_API_KEY="$(${pkgs.coreutils}/bin/cat ${config.age.secrets.openrouter-api-key.path})"

      # -- Oh My Posh prompt --
      if command -v oh-my-posh &>/dev/null; then
        eval "$(oh-my-posh init zsh --config ${config.xdg.configHome}/oh-my-posh/config.json)"
      fi

      # -- fzf-history-widget (Ctrl+R) --
      if command -v fzf &>/dev/null; then
        fzf-history-widget() {
          local selected cmd

          selected=$(
            history 1 | awk '!seen[$0]++' | fzf \
              --height=40% \
              --layout=reverse \
              --border \
              --prompt='History> ' \
              --query="$LBUFFER" \
              --scheme=history
          ) || return

          cmd=$(print -r -- "$selected" | sed -E 's/^[[:space:]]*[0-9]+[* ]?[[:space:]]*//')
          LBUFFER=$cmd
          zle redisplay
        }

        zle -N fzf-history-widget
        bindkey '^R' fzf-history-widget
        bindkey -M viins '^R' fzf-history-widget
      fi

      # -- Keybindings --
      bindkey '^F' autosuggest-accept
      bindkey '^[[C' autosuggest-accept
      bindkey '^P' up-line-or-history
      bindkey '^N' down-line-or-history

      # -- History search aliases --
      alias -- hist='history 1'

      hgrep() {
        history 1 | command grep --color=auto "$@"
      }

      # -- Custom functions --
      mkcd() {
        mkdir -p $1
        cd $1
      }

      killport() {
        lsof -ti:$1 | xargs kill -9
      }

      cjust_swap_caps_escape_gnome() {
        gsettings set org.gnome.desktop.input-sources xkb-options "['caps:swapescape']"
      }
    '';

    # Profile extra (top of .zshrc, after env vars)
    profileExtra = ''
      # -- Ghostty terminfo fix --
      if [[ "$TERM" == "xterm-ghostty" ]]; then
        export TERM=xterm-256color
      fi

      # Only set DISPLAY fallback in a Wayland session (not TTY).
      # Setting DISPLAY on a TTY can cause issues with Wayland compositors.
      if [[ -n "$WAYLAND_DISPLAY" && -z "$DISPLAY" ]]; then
        export DISPLAY=":0"
      fi
    '';

    # Environment variables
    sessionVariables = {
      # Wayland native support for Electron apps (Slack, etc.)
      NIXOS_OZONE_WL = "1";

      EDITOR = "nvim";
      VISUAL = "zeditor";
      # DISPLAY fallback moved to initExtra — only set in graphical sessions

      # Cursor themes
      XCURSOR_SIZE = "24";
      XCURSOR_THEME = "Adwaita";

      # Zoxide config
      _ZO_DATA_DIR = "${config.xdg.dataHome}/zoxide";
      _ZO_ECHO = "1";
      _ZO_EXCLUDE_DIRS = "${config.home.homeDirectory}/.cache:${config.home.homeDirectory}/.cache/*:${config.home.homeDirectory}/tmp";


    };

    # Shell aliases
    shellAliases = {
      # eza
      e = "eza";
      el = "eza -alF";
      # neovim
      v = "nvim";
      vi = "nvim";
      # zoxide replaces cd
      cd = "z";
      # nixos
      nrs = "sudo nixos-rebuild switch --flake /home/${username}/nixos-config#think";
      # homelab
      hl = "ssh -o IdentitiesOnly=yes crussell@10.10.0.6 'bun /etc/homelab-monitor/collect.ts report'";
      # tunnels
      wycliffe-tunnel = "ssh -L 33000:127.0.0.1:33000 -L 33001:127.0.0.1:33001 crussell@10.10.0.12";
    };

    # Extra PATH entries
    envExtra = ''
      export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"
    '';
  };

  # -- Zoxide --
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };
}

# ── Server Shell Configuration ─────────────────────────────────────
#
# Shared zsh + CLI tools for all server hosts.
# Derived from the thinkpad zsh setup but without GUI/desktop specifics.
# Imported by base-server.nix so all k* machines get it automatically.

{ config, lib, pkgs, ... }:

let
  # Secrets → shell env, mirroring the thinkpad .zshenv pattern
  # (hosts/thinkpad/bubblebox/files/.zshenv): decrypt age secrets with the
  # identity at ~/.config/age/key.txt into a per-login tmpfs cache under
  # $XDG_RUNTIME_DIR, then export. Silent + non-fatal when repo/identity/
  # age binary are absent; idempotent (existing vars left untouched).
  secretsEnv = pkgs.writeShellScript "cn-secrets-env" ''
    set -eu
    _vars_missing() {
      [ -z "''${ZHIPU_API_KEY:-}" ] || [ -z "''${OPENROUTER_API_KEY:-}" ] || [ -z "''${GLOO_API_KEY:-}" ]
    }
    if _vars_missing; then
      _cache="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/cn-secrets.env"
      if [ ! -f "$_cache" ] \
         && [ -f "$HOME/.config/age/key.txt" ] \
         && [ -f "$HOME/Code/cn/secrets/zai-api-key.age" ] \
         && command -v age >/dev/null 2>&1; then
        : >"$_cache".tmp
        chmod 600 "$_cache".tmp
        for _src in \
            "$HOME/Code/cn/secrets/zai-api-key.age" \
            "$HOME/Code/cn/secrets/openrouter-api-key.age" \
            "$HOME/Code/cn/secrets/gloo-api-key.age"; do
          [ -f "$_src" ] || continue
          age -d -i "$HOME/.config/age/key.txt" "$_src" 2>/dev/null >>"$_cache".tmp || :
        done
        if [ -s "$_cache".tmp ]; then
          mv "$_cache".tmp "$_cache"
        else
          rm -f "$_cache".tmp
        fi
      fi
      [ -f "$_cache" ] && . "$_cache"
    fi
  '';

  ohMyPoshConfig = pkgs.writeText "oh-my-posh-config.json" ''
    {
      "$schema": "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json",
      "transient_prompt": {
        "template": "❯ ",
        "foreground": "#B48EAD",
        "foreground_templates": ["{{ if gt .Code 0 }}#BF616A{{ end }}"]
      },
      "console_title_template": "{{if .Root}}(Admin){{end}} {{.PWD}}",
      "blocks": [
        {
          "type": "prompt",
          "alignment": "left",
          "segments": [
            {
              "properties": {
                "cache_duration": "none"
              },
              "template": "{{ .UserName }}",
              "foreground": "#BF616A",
              "type": "session",
              "style": "plain"
            },
            {
              "properties": {
                "cache_duration": "none"
              },
              "template": "{{ if .SSHSession }}@{{ .HostName }}{{ end }}",
              "foreground": "#BF616A",
              "type": "session",
              "style": "plain"
            },
            {
              "properties": {
                "cache_duration": "none"
              },
              "template": " \udb84\udd05 ",
              "foreground": "blue",
              "background": "transparent",
              "type": "nix-shell",
              "style": "powerline"
            },
            {
              "type": "command",
              "style": "plain",
              "foreground": "#26C6DA",
              "background": "transparent",
              "properties": {
                "shell": "sh",
                "command": "sh -lc '. /etc/os-release 2>/dev/null; echo ${
                  "ID:-linux"
                }'",
                "trim_space": true,
                "cache_duration": "none"
              },
              "template": "{{- $id := .Output -}}{{ if eq $id \"arch\" }} 󰣇 {{ else if eq $id \"ubuntu\" }} 󰛛 {{ else if eq $id \"debian\" }} 󰆆 {{ else if eq $id \"fedora\" }} 󰊊 {{ else if or (eq $id \"opensuse\") (eq $id \"opensuse-tumbleweed\") }} 󰔔 {{ else if eq $id \"nixos\" }} 󰓓 {{ else if eq $id \"alpine\" }} 󰌀 {{ else if eq $id \"manjaro\" }} 󰒒 {{ else if eq $id \"gentoo\" }} 󰍍 {{ else if or (eq $id \"centos\") (eq $id \"almalinux\") (eq $id \"rocky\") (eq $id \"rhel\") }} 󰖖 {{ else }} 󰊒 {{ end }}"
            },
            {
              "properties": {
                "cache_duration": "none",
                "style": "full"
              },
              "template": " {{ .Path }} ",
              "foreground": "#81A1C1",
              "type": "path",
              "style": "plain"
            }
          ]
        },
        {
          "type": "prompt",
          "alignment": "left",
          "segments": [
            {
              "properties": {
                "branch_ahead_icon": "<#88C0D0>⇡ </>",
                "branch_behind_icon": "<#88C0D0>⇣ </>",
                "branch_icon": "",
                "cache_duration": "none",
                "fetch_stash_count": true,
                "fetch_status": true,
                "fetch_upstream_icon": true,
                "github_icon": ""
              },
              "template": "{{ .UpstreamIcon }}{{ .HEAD }}{{ if .Working.Changed }}<#FFAFD7>* </>{{ .Working.String }}{{ end }}{{ if and (.Working.Changed) (.Staging.Changed) }} |{{ end }}{{ if .Staging.Changed }}  {{ .Staging.String }}{{ end }} ",
              "foreground": "#6C6C6C",
              "type": "git",
              "style": "plain"
            }
          ]
        },
        {
          "type": "prompt",
          "alignment": "left",
          "segments": [
            {
              "properties": {
                "always_enabled": true,
                "cache_duration": "none"
              },
              "template": "❯ ",
              "foreground": "#B48EAD",
              "type": "status",
              "style": "plain",
              "foreground_templates": ["{{ if gt .Code 0 }}#BF616A{{ end }}"]
            }
          ],
          "newline": true
        }
      ],
      "version": 3
    }
  '';
in {
  # ── Shell ────────────────────────────────────────────────────────
  programs.zsh.enable = true;

  users.users.crussell.shell = pkgs.zsh;

  # Decrypt age secrets (ZHIPU/OPENROUTER/GLOO API keys) into every login
  # shell, so interactive opencode/hermes/CLI sessions inherit them.
  # Mirrors hosts/thinkpad/bubblebox/files/.zshenv — see the pattern docs
  # there (tmpfs-cached, once per login, non-fatal when absent).
  environment.etc."zshenv".text = ''
    if [ "$USER" = "crussell" ] && [ -z "''${__CN_SECRETS_ENV_LOADED:-}" ]; then
      export __CN_SECRETS_ENV_LOADED=1
      . ${secretsEnv}
    fi
  '';

  # ── CLI packages ─────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    age
    oh-my-posh
    fzf
    eza
    zoxide
    bat
    fd
    ghostty.terminfo
  ];

  # ── Zsh system config ────────────────────────────────────────────
  programs.zsh = {
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;

    histSize = 100000;
    histFile = "$HOME/.local/state/zsh/history";

    setOptions = [
      "HIST_SAVE_NO_DUPS"
      "HIST_IGNORE_DUPS"
      "HIST_IGNORE_SPACE"
      "SHARE_HISTORY"
      "EXTENDED_HISTORY"
      "HIST_EXPIRE_DUPS_FIRST"
    ];

    promptInit = ''
      # -- Oh My Posh prompt --
      if command -v oh-my-posh &>/dev/null; then
        eval "$(oh-my-posh init zsh --config ${ohMyPoshConfig})"
      fi
    '';

    interactiveShellInit = ''
        # -- Vi keymap --
        bindkey -v

        # -- fzf-history-widget (Ctrl+R) --
        ${builtins.readFile ./fzf-history-widget.zsh}
        bindkey -M vicmd '^R' fzf-history-widget

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

        # -- Shell aliases --
        alias e='eza'
        alias el='eza -alF'
        alias ll='eza -l --icons'
        alias la='eza -la --icons'
        alias cd='z'
      alias v='vim'
      alias vi='vim'

        # -- Zoxide init --
        if command -v zoxide &>/dev/null; then
          eval "$(zoxide init zsh)"
        fi
    '';
  };

  # Ensure zsh history directory and minimal .zshrc exist
  # (prevents zsh-newuser-install wizard on first login)
  systemd.tmpfiles.rules = [
    "d /home/crussell/.local/state/zsh 0755 crussell users -"
    "f /home/crussell/.zshrc 0644 crussell users -"
  ];
}

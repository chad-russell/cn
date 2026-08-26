# /usr/share/dev-shell/.zshrc — interactive zsh config.
# Ported from thinkpad/zsh.nix (viins, oh-my-posh, fzf Ctrl+R, zoxide,
# history, aliases, helper functions). Secrets deferred (not wired here yet).

# ---- History -----------------------------------------------------------
HISTFILE="$HOME/.local/state/zsh/history"
mkdir -p "$(dirname "$HISTFILE")"
HISTSIZE=100000
SAVEHIST=100000
setopt EXTENDED_HISTORY      # timestamp + duration per entry
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY         # share between sessions
setopt INC_APPEND_HISTORY

# ---- Completion --------------------------------------------------------
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

# ---- Keymap: viins -----------------------------------------------------
bindkey -v
export KEYTIMEOUT=1
# Restore some readline comforts in viins (don't block on <Esc>-combo).
bindkey '^P' up-line-or-history
bindkey '^N' down-line-or-history
bindkey '^F' autosuggest-accept 2>/dev/null
bindkey '^R' fzf-history-widget

# ---- Autosuggestions + syntax highlighting (from plugins) -------------
# These ship as zsh plugins; we load minimal inlined versions below.

# ---- oh-my-posh --------------------------------------------------------
if command -v oh-my-posh >/dev/null 2>&1; then
  # --strict: resolve the executable through PATH at prompt time. oh-my-posh is
  # a bubblebox package, and `init` runs INSIDE its sandbox — without --strict
  # it bakes the sandbox-internal path (/usr/bin/oh-my-posh) into the init
  # script, which doesn't exist on the host. --strict emits a bare
  # PATH-resolvable name instead (the ~/.local/bin wrapper), ~22ms/prompt cost.
  eval "$(oh-my-posh init zsh --strict --config "${XDG_CONFIG_HOME:-$HOME/.config}/oh-my-posh.json")"
fi

# ---- zoxide (smart cd) -------------------------------------------------
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

# ---- fzf history widget (Ctrl+R) ---------------------------------------
# Ported from modules/fzf-history-widget.zsh
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

# ---- Aliases -----------------------------------------------------------
alias e='eza'
alias el='eza -alF'
alias vi='nvim'
alias v='nvim'
alias hist='history 1'
# Gloo SSH tunnel to bee (start manually; matches old config)
alias wycliffe-tunnel='ssh -L 33000:127.0.0.1:33000 -L 33001:127.0.0.1:33001 crussell@10.10.0.12'

# ---- Functions ---------------------------------------------------------
mkcd() { mkdir -p "$1" && cd "$1"; }
killport() { lsof -ti:"$1" | xargs -r kill -9; }
hgrep() { history 1 | command grep --color=auto "$@"; }

# cjust — thinkpad task menu (hosts/thinkpad/Justfile). `just`+`fzf` are baked
# into the host image. No args → fuzzy recipe chooser (`just --choose`); any
# args pass straight through to just. Works from any cwd.
cjust() {
  local jf="$HOME/Code/cn/hosts/thinkpad/Justfile"
  if (( $# == 0 )); then
    just --justfile "$jf" --choose
  else
    just --justfile "$jf" "$@"
  fi
}

# ---- Tool integrations ------------------------------------------------
# bat as a manpager and color cat
if command -v bat >/dev/null 2>&1; then
  export MANPAGER="sh -c 'col -bx | bat -l man -p'"
  export BAT_THEME="TwoDark"
fi
# fzf + ripgrep integration
if command -v fzf >/dev/null 2>&1; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
fi

# ---- SSH agent forwarding guard (best-effort) --------------------------
# Ensure SSH_AUTH_SOCK is usable across toolbox/host boundary.
if [ -z "$SSH_AUTH_SOCK" ] && [ -S "$XDG_RUNTIME_DIR/ssh-agent.socket" ]; then
  export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"
fi

# >>> railway initialize >>>
source "$HOME/.railway/env"
# <<< railway initialize <<<

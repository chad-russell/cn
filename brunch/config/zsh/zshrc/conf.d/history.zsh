# History configuration

# XDG-compliant history location
export HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"

# History limits
HISTSIZE="100000"
SAVEHIST="100000"

# Use fcntl lock for better performance
setopt HIST_FCNTL_LOCK

# Enabled history options
enabled_opts=(
  EXTENDED_HISTORY HIST_EXPIRE_DUPS_FIRST HIST_IGNORE_DUPS HIST_IGNORE_SPACE
  SHARE_HISTORY
)
for opt in "${enabled_opts[@]}"; do
  setopt "$opt"
done
unset opt enabled_opts

# Disabled history options
disabled_opts=(
  APPEND_HISTORY HIST_FIND_NO_DUPS HIST_IGNORE_ALL_DUPS HIST_SAVE_NO_DUPS
)
for opt in "${disabled_opts[@]}"; do
  unsetopt "$opt"
done
unset opt disabled_opts

alias -- hist='history 1'

function hgrep {
  history 1 | command grep --color=auto "$@"
}

if command -v fzf &>/dev/null; then
  function fzf-history-widget {
    local selected command

    selected=$(
      history 1 | awk '!seen[$0]++' | fzf \
        --height=40% \
        --layout=reverse \
        --border \
        --prompt='History> ' \
        --query="$LBUFFER" \
        --scheme=history
    ) || return

    command=$(print -r -- "$selected" | sed -E 's/^[[:space:]]*[0-9]+[* ]?[[:space:]]*//')
    LBUFFER=$command
    zle redisplay
  }

  zle -N fzf-history-widget
fi

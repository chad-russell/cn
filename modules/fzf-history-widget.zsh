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
fi

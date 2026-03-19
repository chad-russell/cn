# Keybindings

# Use viins keymap as the default
bindkey -v

# Ctrl+F: accept autosuggestion (from zsh-autosuggestions)
bindkey '^F' autosuggest-accept

# Right arrow: accept autosuggestion or move cursor forward (viins mode)
bindkey '^[[C' autosuggest-accept

# Ctrl+P: previous line in history (like up arrow)
bindkey '^P' up-line-or-history

# Ctrl+N: next line in history (like down arrow)
bindkey '^N' down-line-or-history

if zle -la | grep -qx 'fzf-history-widget'; then
  bindkey '^R' fzf-history-widget
  bindkey -M viins '^R' fzf-history-widget
fi

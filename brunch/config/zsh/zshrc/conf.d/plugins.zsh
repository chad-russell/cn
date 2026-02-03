# Plugin loading

# Plugin directory (managed by Brioche/Brunch)
ZPLUGINDIR="${ZDOTDIR}/plugins"

# Load zsh-autosuggestions (must be loaded before syntax highlighting)
# Try both .zsh and .plugin.zsh files
if [[ -f "$ZPLUGINDIR/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$ZPLUGINDIR/zsh-autosuggestions/zsh-autosuggestions.zsh"
  ZSH_AUTOSUGGEST_STRATEGY=(history)
elif [[ -f "$ZPLUGINDIR/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh" ]]; then
  source "$ZPLUGINDIR/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh"
  ZSH_AUTOSUGGEST_STRATEGY=(history)
fi

# Load oh-my-posh (prompt engine)
if command -v oh-my-posh &>/dev/null; then
  eval "$(oh-my-posh init zsh --config ~/.config/oh-my-posh/config.json)"
fi

# Load zoxide (smarter cd command)
if command -v zoxide &>/dev/null; then
  eval "$(zoxide init zsh)"
fi

# Load zsh-syntax-highlighting (MUST BE LAST)
# Try both .zsh and .plugin.zsh files
if [[ -f "$ZPLUGINDIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
  source "$ZPLUGINDIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
  ZSH_HIGHLIGHT_HIGHLIGHTERS+=()
elif [[ -f "$ZPLUGINDIR/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh" ]]; then
  source "$ZPLUGINDIR/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh"
  ZSH_HIGHLIGHT_HIGHLIGHTERS+=()
fi

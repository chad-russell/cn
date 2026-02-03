# Command aliases

# eza aliases (modern ls replacement)
if command -v eza &>/dev/null; then
  alias -- e=eza
  alias -- el='eza -alF'
fi

# zoxide alias (smarter cd - replace cd with z)
# Comment out if you prefer to keep cd as-is and use z explicitly
if command -v zoxide &>/dev/null; then
  alias -- cd=z
fi

# nvim aliases (neovim)
alias -- v=nvim
alias -- vi=nvim

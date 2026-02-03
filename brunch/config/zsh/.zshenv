# Set ZDOTDIR to XDG-compliant location
# This allows us to keep all zsh configs in ~/.config/zsh/zshrc/
# instead of scattering dotfiles in $HOME
export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh/zshrc"

# Create necessary directories
mkdir -p "$ZDOTDIR"
mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/zsh"
mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/zsh"

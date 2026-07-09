# /usr/share/dev-shell/.zshenv — read first by every zsh.
# Keep it to environment/PATH only (no interactive stuff here).

# Host $HOME is shared with the toolbox; user-local bins if present.
typeset -U path  # dedupe PATH
path=(
  $HOME/.local/bin
  $HOME/.cargo/bin
  $path
)

# fnm-managed node/npm on PATH. fnm env wires the current node version in.
# (Sourced in .zshrc; here we only export the stable bits.)
export EDITOR=nvim
export VISUAL=nvim
export PAGER=bat
export LESS='-R -F -X'

# zoxide data dir
export _ZO_DATA_DIR="$HOME/.local/share/zoxide"
export _ZO_ECHO=1
export _ZO_EXCLUDE_DIRS="$HOME/.cache:$HOME/tmp"

# Cursor (kept from old config; applies to GUI apps that read it, harmless here)
export XCURSOR_SIZE=24

# Suppress GTK/Qt noise for CLI tools
export GIO_EXTRA_MODULES=

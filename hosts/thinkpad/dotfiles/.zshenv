# /usr/share/dev-shell/.zshenv — read first by every zsh.
# Keep it to environment/PATH only (no interactive stuff here).

# Host $HOME is shared with the toolbox; user-local bins if present.
typeset -U path  # dedupe PATH
path=(
  $HOME/.local/bin
  $HOME/.cargo/bin
  # shellbox exports — still here during the bubblebox migration transition
  # because opencode hasn't moved to the host yet (waiting on host-image
  # rebuild for nodejs/npm). Remove this line in Phase B, after:
  #   1. `cjust opencode-install` has run successfully, AND
  #   2. `~/.local/bin/opencode` exists and `opencode auth login` works.
  # Until then, this entry keeps the shellbox opencode wrapper reachable.
  $HOME/.local/share/shellbox/exports/bin
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

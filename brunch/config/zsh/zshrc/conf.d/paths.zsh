# PATH configuration

# Clean PATH array (remove duplicates)
typeset -U path PATH

# Add user directories first
path=(
  ~/.local/bin
  ~/.local/share/brioche/installed/bin
  ~/.cargo/bin
  ~/.bun/bin
  $path
)

export PATH

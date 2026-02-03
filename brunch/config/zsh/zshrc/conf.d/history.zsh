# History configuration

# XDG-compliant history location
export HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"

# History limits
HISTSIZE="50000"
SAVEHIST="50000"

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

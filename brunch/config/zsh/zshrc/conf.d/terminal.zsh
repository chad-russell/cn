# Terminal compatibility fixes
# xterm-ghostty terminfo causes issues with zsh (double input, broken clear)
# Fall back to xterm-256color which works correctly
if [[ "$TERM" == "xterm-ghostty" ]]; then
  export TERM=xterm-256color
fi

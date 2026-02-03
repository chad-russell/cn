# Source all modular configs in conf.d/
for file in $ZDOTDIR/conf.d/*.zsh(N); do
  source "$file"
done

# Initialize zsh completion system
autoload -Uz compinit
compinit -d "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump-${HOST}"

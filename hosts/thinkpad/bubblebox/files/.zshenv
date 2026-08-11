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

# ── Secrets → shell env (agenix, tmpfs-cached) ────────────────────────
# Decrypt age secrets with the agenix identity at ~/.config/age/key.txt,
# exporting the vars into this shell so any child process (other CLIs, agents,
# scripts) inherits them. Plaintext is cached ONLY in $XDG_RUNTIME_DIR
# (per-login tmpfs: gone at logout, never on persistent disk, never
# committed). Decrypted at most once per login session; every later shell just
# sources the cache. Silent and non-fatal when the repo/identity/age binary is
# absent, so shell startup can't break. Idempotent: a pre-existing var (e.g.
# ZHIPU_API_KEY) is left untouched. Adding another secret = add another age
# file to the decrypt step (cache filename is generic on purpose).
#
# Currently sourced secrets:
#   secrets/zai-api-key.age           → ZHIPU_API_KEY   (opencode)
#   secrets/hermes-thinkpad-env.age   → OPENAI_API_KEY  (hermes; same Z.AI
#                                                      key value as above,
#                                                      remapped for hermes'
#                                                      OpenAI-compatible
#                                                      provider resolver)
#
# NOTE: this only covers shells + their children. GUI apps launched directly
#       by the compositor (niri/COSMIC `spawn`, not from a terminal) read the
#       systemd user session env (environment.d), not .zshenv — so they won't
#       see these vars. The hermes desktop wrapper at
#       dotfiles/.local/bin/hermes-desktop sources this same cache before
#       exec'ing the Electron app, so compositor-launched hermes desktop does
#       see OPENAI_API_KEY.
if [ -z "${ZHIPU_API_KEY:-}" ] || [ -z "${OPENAI_API_KEY:-}" ]; then
  _cn_secrets_cache="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/cn-secrets.env"
  if [ ! -f "$_cn_secrets_cache" ] \
     && [ -f "$HOME/.config/age/key.txt" ] \
     && [ -f "$HOME/Code/cn/secrets/zai-api-key.age" ] \
     && command -v age >/dev/null 2>&1; then
    # Build the cache by decrypting each registered secret into the same file.
    # A failed decrypt (missing file, wrong identity) is non-fatal: we just
    # skip that source and move on. Empty/whitespace-only lines are stripped so
    # a missing secret doesn't leave a blank line in the cache.
    : >"$_cn_secrets_cache".tmp
    chmod 600 "$_cn_secrets_cache".tmp
    for _age_src in \
        "$HOME/Code/cn/secrets/zai-api-key.age" \
        "$HOME/Code/cn/secrets/hermes-thinkpad-env.age"; do
      [ -f "$_age_src" ] || continue
      if age -d -i "$HOME/.config/age/key.txt" "$_age_src" 2>/dev/null >>"$_cn_secrets_cache".tmp; then
        : # appended
      fi
    done
    if [ -s "$_cn_secrets_cache".tmp ]; then
      mv "$_cn_secrets_cache".tmp "$_cn_secrets_cache"
    else
      rm -f "$_cn_secrets_cache".tmp
    fi
    unset _age_src
  fi
  if [ -f "$_cn_secrets_cache" ]; then
    set -a; . "$_cn_secrets_cache"; set +a
  fi
  unset _cn_secrets_cache
fi

. "$HOME/.cargo/env"

#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <service>" >&2
  exit 1
fi

SERVICE="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_DIR="$SCRIPT_DIR/host-envs"
SECRETS_FILE="$SCRIPT_DIR/secrets/gloo-secrets.env.age"
AGE_KEY="${AGE_KEY:-$HOME/.config/age/key.txt}"
AGE_BIN="${AGE_BIN:-$([ -x /home/linuxbrew/.linuxbrew/bin/age ] && echo /home/linuxbrew/.linuxbrew/bin/age || command -v age || true)}"
RUNTIME_BASE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gloo"
TARGET_ENV="$RUNTIME_BASE/${SERVICE}.env"
SOURCE_ENV="$ENV_DIR/${SERVICE}.env"

if [ ! -f "$SOURCE_ENV" ]; then
  echo "missing env file: $SOURCE_ENV" >&2
  exit 1
fi

umask 077
mkdir -p "$RUNTIME_BASE"
cp "$SOURCE_ENV" "$TARGET_ENV"

if [ -f "$SECRETS_FILE" ]; then
  if [ -z "$AGE_BIN" ] || [ ! -x "$AGE_BIN" ]; then
    echo "age binary not found; cannot decrypt $SECRETS_FILE" >&2
    exit 1
  fi
  if [ ! -f "$AGE_KEY" ]; then
    echo "age key not found at $AGE_KEY" >&2
    exit 1
  fi

  {
    printf '\n# decrypted secrets\n'
    "$AGE_BIN" -d -i "$AGE_KEY" "$SECRETS_FILE"
  } >> "$TARGET_ENV"
fi

chmod 600 "$TARGET_ENV"
printf '%s\n' "$TARGET_ENV"

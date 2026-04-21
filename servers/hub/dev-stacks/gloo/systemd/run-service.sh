#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <service>" >&2
  exit 1
fi

SERVICE="$1"
STACK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_BASE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gloo"
RUNTIME_ENV="$RUNTIME_BASE/${SERVICE}.env"

if [ ! -f "$RUNTIME_ENV" ]; then
  "$STACK_DIR/systemd/render-runtime-env.sh" "$SERVICE" >/dev/null
fi

set -a
# shellcheck disable=SC1090
source "$RUNTIME_ENV"
set +a

export PATH="$HOME/.local/bin:$PATH"

case "$SERVICE" in
  gpl)
    cd "$HOME/Gloo/360-gpl"
    exec npx next dev -p 3106
    ;;
  hb-api)
    cd "$HOME/Gloo/360-hummingbird"
    exec pnpm --filter api dev
    ;;
  hb-web)
    cd "$HOME/Gloo/360-hummingbird"
    exec pnpm --filter web dev -- --host 0.0.0.0 --port 3100
    ;;
  storyhub)
    cd "$HOME/Gloo/360-hummingbird/storyhub"
    exec npx next dev --port 3007
    ;;
  storyhub-worker)
    if ! command -v bun >/dev/null 2>&1; then
      echo "bun is required for storyhub-worker but is not installed" >&2
      exit 1
    fi
    cd "$HOME/Gloo/360-hummingbird"
    exec pnpm --filter storyhub-worker dev
    ;;
  polymer)
    export PATH="/home/linuxbrew/.linuxbrew/opt/node@24/bin:$PATH"
    cd "$HOME/Gloo/360-polymer/apps/polymer"
    rm -f .next/dev/lock
    exec pnpm exec next dev --turbo --hostname 0.0.0.0 --port 3001
    ;;
  *)
    echo "unknown service: $SERVICE" >&2
    exit 1
    ;;
esac

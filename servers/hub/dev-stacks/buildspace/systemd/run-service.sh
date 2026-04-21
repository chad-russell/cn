#!/usr/bin/env bash
# Run a buildspace dev server.
# Sources ~/Code/bs/buildspace/.env and execs the appropriate bun command.
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 <service>" >&2
    exit 1
fi

SERVICE="$1"
REPO_DIR="$HOME/Code/bs/buildspace"
ENV_FILE="$REPO_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "missing env file: $ENV_FILE" >&2
    exit 1
fi

cd "$REPO_DIR"

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

export PATH="$HOME/.bun/bin:$HOME/.local/bin:$PATH"

case "$SERVICE" in
  marketplace)
    exec bun --filter @buildspace/marketplace dev
    ;;
  login)
    exec bun --filter @buildspace/login dev
    ;;
  runtime)
    exec bun --filter @buildspace/runtime dev
    ;;
  studio)
    exec bun --filter @buildspace/studio dev
    ;;
  docs)
    exec bun --filter @buildspace/docs dev
    ;;
  super-admin)
    exec bun --filter @buildspace/super-admin dev
    ;;
  jobs)
    exec bun --filter @buildspace/jobs-app dev
    ;;
  *)
    echo "unknown service: $SERVICE" >&2
    exit 78
    ;;
esac

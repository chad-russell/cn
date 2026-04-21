#!/usr/bin/env bash
# Bootstrap GPL: push schema + seed data.
# Assumes infra is running and runtime env is already rendered.
set -euo pipefail

RUNTIME_BASE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gloo"
export PATH="/home/linuxbrew/.linuxbrew/opt/node@24/bin:$HOME/.local/bin:$HOME/.bun/bin:$PATH"

set -a
# shellcheck disable=SC1090
source "$RUNTIME_BASE/gpl.env"
set +a

cd "$HOME/Gloo/360-gpl"
pnpm db:push
pnpm db:seed

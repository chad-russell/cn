#!/usr/bin/env bash
# Bootstrap Storyhub: seed data.
# Assumes infra is running and runtime env is already rendered.
set -euo pipefail

RUNTIME_BASE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gloo"
export PATH="/home/linuxbrew/.linuxbrew/opt/node@24/bin:$HOME/.local/bin:$HOME/.bun/bin:$PATH"

set -a
# shellcheck disable=SC1090
source "$RUNTIME_BASE/storyhub.env"
set +a

cd "$HOME/Gloo/360-hummingbird/storyhub-prisma"
pnpm seed

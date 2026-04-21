#!/usr/bin/env bash
# Start GPL dev services on the host.
# Usage: ./dev.sh [gpl|hb-api|hb-web|polymer|all]
set -euo pipefail

ENV_DIR="$(cd "$(dirname "$0")" && pwd)/host-envs"

# Ensure infra is running
COMPOSE_FILE="$(cd "$(dirname "$0")" && pwd)/compose.yaml"
echo "Checking infra services..."
podman compose -f "$COMPOSE_FILE" up -d

# Wait for postgres
echo "Waiting for postgres..."
for i in $(seq 1 30); do
    if podman exec gpl-postgres-1 pg_isready -U postgres &>/dev/null; then
        break
    fi
    sleep 1
done

start_service() {
    local name="$1"
    shift
    case "$name" in
        gpl)
            echo "Starting GPL app on :3106..."
            cd ~/Gloo/360-gpl
            env $(grep -v '^#' "$ENV_DIR/gpl.env" | xargs) \
                pnpm dev -- -p 3106
            ;;
        hb-api)
            echo "Starting Hummingbird API on :8000..."
            cd ~/Gloo/360-hummingbird
            env $(grep -v '^#' "$ENV_DIR/hb-api.env" | xargs) \
                pnpm --filter api dev
            ;;
        hb-web)
            echo "Starting Hummingbird Web on :3100..."
            cd ~/Gloo/360-hummingbird
            env $(grep -v '^#' "$ENV_DIR/hb-web.env" | xargs) \
                pnpm --filter web dev -- --host 0.0.0.0 --port 3000
            ;;
        polymer)
            echo "Starting Polymer on :3001..."
            # Polymer requires Node 24
            export PATH="/home/linuxbrew/.linuxbrew/opt/node@24/bin:$PATH"
            cd ~/Gloo/360-polymer
            cd apps/polymer
            rm -f .next/dev/lock
            env $(grep -v '^#' "$ENV_DIR/polymer.env" | xargs) \
                pnpm exec next dev --turbo --hostname 0.0.0.0 --port 3001
            ;;
        *)
            echo "Unknown service: $name"
            echo "Usage: $0 [gpl|hb-api|hb-web|polymer|all]"
            exit 1
            ;;
    esac
}

if [ $# -eq 0 ] || [ "$1" = "all" ]; then
    echo "Starting all services in background..."
    echo "Use individual terminals for better log visibility:"
    echo "  $0 gpl"
    echo "  $0 hb-api"
    echo "  $0 hb-web"
    echo "  $0 polymer"
    echo ""
    echo "Starting all in this terminal (Ctrl+C to stop)..."

    # Start each in background, wait for any to exit
    trap 'kill 0' EXIT

    start_service hb-api &
    start_service hb-web &
    start_service polymer &
    start_service gpl &

    wait
else
    start_service "$1"
fi

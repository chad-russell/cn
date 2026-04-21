#!/usr/bin/env bash
# Start GPL dev services on the host.
# Usage: ./dev.sh [gpl|hb-api|hb-web|polymer|all]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_DIR="$SCRIPT_DIR/host-envs"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"

# Load an env file for shell sourcing (skips comments and blank lines)
load_env() {
    local envfile="$1"
    set -a
    while IFS= read -r line; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        eval "$line"
    done < "$envfile"
    set +a
}

# Ensure infra is running
echo "Checking infra services..."
podman compose -f "$COMPOSE_FILE" up -d

# Wait for postgres
echo "Waiting for postgres..."
for i in $(seq 1 30); do
    if podman exec gpl_postgres_1 pg_isready -U postgres &>/dev/null; then
        echo "Postgres ready."
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
            load_env "$ENV_DIR/gpl.env"
            cd ~/Gloo/360-gpl
            exec npx next dev -p 3106
            ;;
        hb-api)
            echo "Starting Hummingbird API on :8000..."
            load_env "$ENV_DIR/hb-api.env"
            cd ~/Gloo/360-hummingbird
            exec pnpm --filter api dev
            ;;
        hb-web)
            echo "Starting Hummingbird Web on :3100..."
            load_env "$ENV_DIR/hb-web.env"
            cd ~/Gloo/360-hummingbird
            exec pnpm --filter web dev -- --host 0.0.0.0 --port 3000
            ;;
        polymer)
            echo "Starting Polymer on :3001..."
            export PATH="/home/linuxbrew/.linuxbrew/opt/node@24/bin:$PATH"
            load_env "$ENV_DIR/polymer.env"
            cd ~/Gloo/360-polymer/apps/polymer
            rm -f .next/dev/lock
            exec pnpm exec next dev --turbo --hostname 0.0.0.0 --port 3001
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
    echo "For better log visibility, use separate terminals:"
    echo "  $0 gpl"
    echo "  $0 hb-api"
    echo "  $0 hb-web"
    echo "  $0 polymer"
    echo ""
    echo "Starting all in this terminal (Ctrl+C to stop all)..."

    trap 'kill 0' EXIT

    (start_service hb-api) &
    (start_service hb-web) &
    (start_service polymer) &
    (start_service gpl) &

    wait
else
    start_service "$1"
fi

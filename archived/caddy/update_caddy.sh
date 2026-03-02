#!/bin/bash
# Update Caddy configuration and restart the container

set -e

CONTAINER_NAME="caddy-proxy"
LOCAL_CADDYFILE="/var/home/crussell/Code/cn/caddy/Caddyfile"
REMOTE_PATH="/home/crussell/caddy/Caddyfile"

if [ ! -f "$LOCAL_CADDYFILE" ]; then
    echo "Error: Caddyfile not found at $LOCAL_CADDYFILE"
    exit 1
fi

echo "Copying Caddyfile to k2..."
cat "$LOCAL_CADDYFILE" | ssh -i ~/.ssh/id_ed25519 k2 "cat > $REMOTE_PATH"

echo "Restarting Caddy container..."
ssh -i ~/.ssh/id_ed25519 k2 "docker restart $CONTAINER_NAME"

echo "Waiting for Caddy to start..."
sleep 3

echo "Checking Caddy status..."
ssh -i ~/.ssh/id_ed25519 k2 "docker ps | grep $CONTAINER_NAME" || {
    echo "Error: Caddy container failed to start"
    exit 1
}

echo "✓ Caddy updated and running successfully"

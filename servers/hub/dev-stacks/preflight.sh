#!/usr/bin/env bash
set -euo pipefail

echo "=== Checking CLI tools ==="
for cmd in podman git bun; do
    if command -v "$cmd" &>/dev/null; then
        echo "  ✓ $cmd"
    else
        echo "  ✗ $cmd (missing)"
    fi
done

echo ""
echo "=== Checking Gloo prerequisites ==="
for path in \
    "$HOME/Gloo/gloo-control-plane" \
    "$HOME/Gloo/360-gpl" \
    "$HOME/Gloo/360-hummingbird" \
    "$HOME/Gloo/360-polymer"; do
    if [ -d "$path" ]; then
        echo "  ✓ $path"
    else
        echo "  ✗ $path (missing)"
    fi
done

for envfile in \
    "$HOME/Gloo/gloo-control-plane/envs/gpl.env" \
    "$HOME/Gloo/gloo-control-plane/envs/hb-api.env" \
    "$HOME/Gloo/gloo-control-plane/envs/hb-web.env" \
    "$HOME/Gloo/gloo-control-plane/envs/polymer.env" \
    "$HOME/Gloo/gloo-control-plane/envs/pgadmin.env"; do
    if [ -f "$envfile" ]; then
        echo "  ✓ $envfile"
    else
        echo "  ✗ $envfile (missing)"
    fi
done

echo ""
echo "=== Checking Buildspace prerequisites ==="
for path in "$HOME/Code/bs/buildspace"; do
    if [ -d "$path" ]; then
        echo "  ✓ $path"
    else
        echo "  ✗ $path (missing)"
    fi
done

for envfile in \
    "$HOME/Code/bs/buildspace/.env"; do
    if [ -f "$envfile" ]; then
        echo "  ✓ $envfile"
    else
        echo "  ✗ $envfile (missing)"
    fi
done

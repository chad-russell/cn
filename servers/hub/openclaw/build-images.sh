#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_DIR="$SCRIPT_DIR/images"

podman build -t localhost/openclaw-hub:latest -f "$IMAGE_DIR/Containerfile" "$IMAGE_DIR"
podman build -t openclaw-sandbox:bookworm-slim -f "$IMAGE_DIR/Dockerfile.sandbox" "$IMAGE_DIR"
podman build -t openclaw-sandbox-browser:bookworm-slim -f "$IMAGE_DIR/Dockerfile.sandbox-browser" "$IMAGE_DIR"

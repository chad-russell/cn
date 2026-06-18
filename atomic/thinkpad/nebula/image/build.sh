#!/usr/bin/env bash
# Build the Nebula container image (rootful — matches the rootful Quadlet).
# Run on the host (Silverblue ships podman).
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="localhost/nebula:thinkpad"

sudo podman build -t "$IMAGE" "$SELF_DIR"
echo "Built $IMAGE"

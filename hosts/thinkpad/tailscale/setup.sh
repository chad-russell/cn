#!/usr/bin/env bash
# One-shot setup for the on-demand Tailscale container:
#   1. pull the upstream image (idempotent)
#   2. install the Quadlet unit (no enable, no start — on-demand by design)
#
# Idempotent — safe to re-run. Re-running picks up an updated image and/or an
# edited tailscale.container.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="docker.io/tailscale/tailscale:latest"

echo "==> [1/2] Pulling ${IMAGE}..."
sudo podman pull "$IMAGE"

echo
echo "==> [2/2] Installing Quadlet (NOT enabling — on-demand by design)..."
"$SELF_DIR/install.sh"

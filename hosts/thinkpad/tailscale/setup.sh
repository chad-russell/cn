#!/usr/bin/env bash
# One-shot setup for the on-demand Tailscale container:
#   1. pull the upstream image (idempotent)
#
# The Quadlet ships IN THE HOST IMAGE (host-image/quadlets/tailscale.container,
# on-demand by design — no boot enablement). Start with
# `sudo systemctl start tailscale`.
#
# Idempotent — safe to re-run. Re-running picks up an updated image and/or an
# edited tailscale.container.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="docker.io/tailscale/tailscale:latest"

echo "==> Pulling ${IMAGE}..."
sudo podman pull "$IMAGE"


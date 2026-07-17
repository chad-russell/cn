#!/usr/bin/env bash
# Build the restic-backup image into root podman storage. (sudo)
# Base image is pulled on first build; rebuilds reuse cached layers.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sudo podman build -t localhost/restic-backup:think "$SELF_DIR"
echo "Built localhost/restic-backup:think"

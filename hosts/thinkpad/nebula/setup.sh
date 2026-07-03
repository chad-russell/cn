#!/usr/bin/env bash
# One-shot first-time setup for the Nebula container:
#   1. build the image            (image/build.sh)
#   2. seed the config volume     (seed.sh)
#   3. install the Quadlet + enable+start   (install.sh)
#
# Idempotent — safe to re-run.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [1/3] Building image..."
"$SELF_DIR/image/build.sh"

echo
echo "==> [2/3] Seeding config volume..."
"$SELF_DIR/seed.sh"

echo
echo "==> [3/3] Installing Quadlet + enabling service..."
"$SELF_DIR/install.sh"

#!/usr/bin/env bash
# One-shot first-time setup for the Nebula container:
#   1. build the image            (image/build.sh)
#   2. seed the config volume     (seed.sh)
#
# The Quadlet itself ships IN THE HOST IMAGE (host-image/quadlets/
# nebula.container, enabled at boot) — nothing installs into /etc anymore.
# Re-run this after editing config.yaml (seed) or the container image (build);
# then `sudo systemctl restart nebula`.
#
# Idempotent — safe to re-run.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [1/2] Building image..."
"$SELF_DIR/image/build.sh"

echo
echo "==> [2/2] Seeding config volume..."
"$SELF_DIR/seed.sh"


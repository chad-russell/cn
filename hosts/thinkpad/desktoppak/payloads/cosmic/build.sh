#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FEDORA_MAJOR_VERSION="${FEDORA_MAJOR_VERSION:-44}"
IMAGE="${COSMIC_IMAGE:-localhost/cosmic-session:dev}"

podman build \
  --pull=newer \
  --build-arg "FEDORA_MAJOR_VERSION=${FEDORA_MAJOR_VERSION}" \
  -t "$IMAGE" \
  -f "$SELF_DIR/Containerfile" \
  "$SELF_DIR"

echo
printf 'Built rootfs image: %s\n' "$IMAGE"
printf 'Next: python3 ../../cli/desktoppak.py install cosmic %s\n' "$IMAGE"

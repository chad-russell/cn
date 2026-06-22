#!/usr/bin/env bash
set -euo pipefail

IMAGE="${NIRI_IMAGE:-localhost/niri-session:dev}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BLUEPRINT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
STATE_ROOT="${DESKTOP_BLUEPRINT_STATE_ROOT:-${BLUEPRINT_DIR}/state}"
ROOTFS_DIR="${DESKTOP_BLUEPRINT_ROOTFS_DIR:-${STATE_ROOT}/rootfs}"
STAMP_FILE="${ROOTFS_DIR}/.image-ref"
REFRESH=0

usage() {
  cat >&2 <<EOF
usage: $(basename "$0") [--refresh]

Extracts the OCI image rootfs for the bwrap prototype into:
  $ROOTFS_DIR
EOF
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --refresh)
      REFRESH=1
      shift
      ;;
    *)
      usage
      ;;
  esac
done

command -v podman >/dev/null 2>&1 || { echo "ERROR: podman not found" >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "ERROR: tar not found" >&2; exit 1; }

if ! podman image exists "$IMAGE"; then
  cat >&2 <<EOF
ERROR: local image not found in your rootless podman storage: $IMAGE

Build it first:
  ./build-rootfs-image.sh

If you intentionally want a different image:
  NIRI_IMAGE=<image-ref> ./prepare-rootfs.sh --refresh
EOF
  exit 1
fi

if [ "$REFRESH" -eq 0 ] && [ -f "$STAMP_FILE" ] && [ "$(cat "$STAMP_FILE")" = "$IMAGE" ] && [ -x "$ROOTFS_DIR/usr/bin/niri" ]; then
  echo "$ROOTFS_DIR"
  exit 0
fi

mkdir -p "$STATE_ROOT"
rm -rf "$ROOTFS_DIR"
mkdir -p "$ROOTFS_DIR"

container_name="desktop-blueprint-rootfs-$$"
cleanup() {
  podman rm -f "$container_name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

podman create --name "$container_name" "$IMAGE" true >/dev/null
podman export "$container_name" | tar -xf - -C "$ROOTFS_DIR"
printf '%s\n' "$IMAGE" > "$STAMP_FILE"

echo "$ROOTFS_DIR"

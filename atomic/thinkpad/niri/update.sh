#!/bin/sh
# Update the image by creating a temporary container, running dnf update, and
# committing the result back into the image.
#
# This refreshes niri / noctalia-git to the newest COPR builds WITHOUT
# rebuilding the world from the Containerfile.
#
# Workflow:
#   ./build.sh   -> build image
#   ./start.sh   -> run desktop in a temporary container
#   ./update.sh  -> refresh packages and save them into the image

set -e

IMAGE=localhost/niri-dev:latest
CONTAINER=niri-dev-update

cleanup() {
    sudo podman rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Updating packages"
sudo podman run --name "$CONTAINER" "$IMAGE" dnf -y update --refresh

# Commit the updated writable layer back into the image.
echo "==> Saving updated container back into $IMAGE"
sudo podman commit "$CONTAINER" "$IMAGE" >/dev/null

echo
echo "==> Done. Start the desktop with:  ./start.sh"

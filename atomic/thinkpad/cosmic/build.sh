#!/bin/sh
# Build only the COSMIC image from Containerfile.
#
# This does not create or start any container.
# Use ./start.sh to launch a temporary desktop container.

set -e

IMAGE=localhost/cosmic-dev:latest

echo "==> Building image $IMAGE from Containerfile"
sudo podman build -t "$IMAGE" .

echo
echo "==> Done. Launch the desktop with:  ./start.sh   (from a free VT)"

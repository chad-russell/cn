#!/usr/bin/env bash
# Connect to the Wycliffe GlobalProtect VPN using the official
# GlobalProtect-openconnect (gpclient) container.
#
# Rootful + host networking: gpclient creates tun0 on the host and installs
# routes so host traffic uses the VPN (same pattern as the nebula container).
# Auth happens in your host browser via gpclient's --browser remote mode,
# which sidesteps the globalprotectcallback: scheme problems entirely.
#
# Usage:      ./connect.sh
# Disconnect: Ctrl+C in this terminal.
set -euo pipefail

PORTAL="wycliffe.gpcloudservice.com"
# Docker Hub only publishes a rolling `snapshot` tag for this image
# (the version tags documented upstream are not actually published).
# snapshot is rebuilt frequently from main; last updated 2026-06-13.
# To pin a known-good build for immutability, append a digest:
#   IMAGE="docker.io/yuezk/globalprotect-openconnect:snapshot@sha256:<digest>"
IMAGE="docker.io/yuezk/globalprotect-openconnect:snapshot"

echo "==> Connecting to Wycliffe GlobalProtect: $PORTAL"
echo "==> A URL will appear below. Open it in your browser (Zen) and complete"
echo "    the Wycliffe SSO login. The tunnel (tun0) comes up once auth completes."
echo "==> Keep this terminal open. Ctrl+C to disconnect."
echo

# --rm            remove the container when it exits
# -it             interactive tty (gpclient prints the URL; Ctrl+C to disconnect)
# --network host  TUN + routes land on the host so host traffic uses the VPN
# --cap-add=NET_ADMIN --device=/dev/net/tun  create/manage the tunnel
#
# The image's ENTRYPOINT is gpclient, so the args below become:
#   gpclient connect wycliffe.gpcloudservice.com --browser remote
sudo podman run --rm -it \
  --network host \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  "$IMAGE" \
  connect "$PORTAL" --browser remote

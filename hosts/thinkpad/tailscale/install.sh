#!/usr/bin/env bash
# Install the Tailscale Quadlet onto the host and reload systemd.
# Run via setup.sh (which pulls the image first), or directly.
#
# Deliberately does NOT enable or start the unit (unlike nebula/install.sh):
# Tailscale is on-demand only on this host. After installing, the first-time
# flow is:
#   sudo systemctl start tailscale
#   sudo podman exec tailscale tailscale up   # prints URL → browser auth
#
# Safe to re-run (idempotent).
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_SRC="$SELF_DIR/tailscale.container"
UNIT_DST="/etc/containers/systemd/tailscale.container"
UNIT="tailscale.service"

[ -f "$UNIT_SRC" ] || { echo "missing $UNIT_SRC" >&2; exit 1; }

sudo -v

# Install the Quadlet source and let systemd generate tailscale.service.
sudo install -m 0644 "$UNIT_SRC" "$UNIT_DST"
sudo systemctl daemon-reload

cat <<EOF

Installed. tailscale.service is registered but NOT enabled at boot and NOT
running (on-demand only).

First-time setup (browser auth, then cached):
  sudo systemctl start tailscale
  sudo podman exec tailscale tailscale up     # prints URL → browser login
  sudo podman exec tailscale tailscale status

Day to day:
  sudo systemctl start tailscale              # VPN on (auto-reconnects from cache)
  sudo systemctl stop tailscale               # VPN off (tunnel torn down)
  sudo journalctl -u tailscale -f

Verify the tunnel:
  ip addr show tailscale0
EOF

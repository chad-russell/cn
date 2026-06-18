#!/usr/bin/env bash
# Install the Nebula Quadlet onto the host, reload systemd, enable + start.
# Run AFTER build.sh and seed.sh (or just use setup.sh, which does all three).
#
# Boot-autostart gotcha: systemd marks Quadlet-generated units as `generated`
# state, and on some systemd versions (e.g. Fedora 44) `systemctl enable`
# refuses them ("Unit ... is transient or generated"). This script tries the
# normal `enable` first; if that's refused, it replicates exactly what enable
# would have done — a wants symlink into the generator output. The Quadlet
# generator runs early at boot (before any target activates), so the symlink
# target always exists by the time multi-user.target evaluates its wants.
#
# Safe to re-run (idempotent).
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_SRC="$SELF_DIR/nebula.container"
UNIT_DST="/etc/containers/systemd/nebula.container"
WANTS_DIR="/etc/systemd/system/multi-user.target.wants"
UNIT="nebula.service"

[ -f "$UNIT_SRC" ] || { echo "missing $UNIT_SRC" >&2; exit 1; }

sudo -v

# 1. Install the Quadlet source and let systemd generate nebula.service.
sudo install -m 0644 "$UNIT_SRC" "$UNIT_DST"
sudo systemctl daemon-reload

# 2. Boot autostart. Try normal enable; fall back to a manual wants symlink
#    for systems that refuse to enable `generated`-state units.
if sudo systemctl enable "$UNIT" 2>/dev/null; then
  ENABLED_VIA="systemctl enable"
else
  sudo mkdir -p "$WANTS_DIR"
  sudo ln -sf /run/systemd/generator/"$UNIT" "$WANTS_DIR/$UNIT"
  sudo systemctl daemon-reload
  ENABLED_VIA="wants symlink -> /run/systemd/generator/$UNIT"
fi

# 3. Start (or restart) the service now.
sudo systemctl restart "$UNIT"

cat <<EOF

Installed. nebula.service is running and will auto-start at boot.
Enabled via: $ENABLED_VIA

Manage it with:
  sudo systemctl status nebula
  sudo systemctl stop nebula      # VPN off (stays off until start or reboot)
  sudo systemctl start nebula     # VPN on
  sudo journalctl -u nebula -f

Verify the overlay:
  ip addr show nebula0
  ping -c2 10.10.0.6              # bees
EOF

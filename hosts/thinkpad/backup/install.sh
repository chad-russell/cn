#!/usr/bin/env bash
# Install the restic backup Quadlets + timers + ntfy notifier onto the host,
# reload systemd, and enable the timers (NOT the services — they are one-shot
# and timer-driven). Run AFTER seed.sh (or just use setup.sh).
#
# The .container files land in /etc/containers/systemd/ and generate
# restic-backup.service / restic-check.service at boot via the Quadlet
# generator. The .timer files and the ntfy template are plain systemd units.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUADLET_DST="/etc/containers/systemd"
SYSTEMD_DST="/etc/systemd/system"

sudo -v
sudo install -d "$QUADLET_DST" "$SYSTEMD_DST"

# Quadlets (.container) -> generated services
for f in restic-backup restic-check; do
  sudo install -m 0644 "$SELF_DIR/$f.container" "$QUADLET_DST/$f.container"
done

# Plain systemd units: timers + ntfy notifier template
for f in restic-backup.timer restic-check.timer restic-ntfy-failure@.service; do
  sudo install -m 0644 "$SELF_DIR/$f" "$SYSTEMD_DST/$f"
done

sudo systemctl daemon-reload

# Enable + start the timers only (services are triggered, not boot-enabled).
sudo systemctl enable --now restic-backup.timer restic-check.timer

cat <<EOF

Installed. Active timers:
  restic-backup.timer  -> daily   (Persistent, RandomizedDelaySec=1h)
  restic-check.timer   -> weekly  (Persistent, RandomizedDelaySec=2h)

Manage:
  sudo systemctl list-timers 'restic-*'
  sudo systemctl start restic-backup.service    # manual run now
  sudo journalctl -u restic-backup.service -f

Re-seed + reinstall any time:
  $SELF_DIR/seed.sh && $SELF_DIR/install.sh
EOF

#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Hub Restic Backup Installation ==="

if [[ $EUID -ne 0 ]]; then
    echo "Please run as root or with sudo"
    exit 1
fi

echo ""
echo "1. Installing restic..."
if command -v dnf &>/dev/null; then
    dnf install -y restic
elif command -v apt &>/dev/null; then
    apt install -y restic
else
    echo "Please install restic manually"
    exit 1
fi

echo ""
echo "2. Creating /etc/restic directory..."
mkdir -p /etc/restic

if [[ ! -f /etc/restic/password ]]; then
    echo "3. Generating password file..."
    openssl rand -hex 32 > /etc/restic/password
    chmod 600 /etc/restic/password
    echo "   Password generated and saved to /etc/restic/password"
else
    echo "3. Password file already exists, skipping..."
fi

echo ""
echo "4. Copying excludes file..."
cp "$SCRIPT_DIR/excludes" /etc/restic/excludes

echo ""
echo "5. Copying backup script..."
cp "$SCRIPT_DIR/restic-backup.sh" /usr/local/bin/
chmod +x /usr/local/bin/restic-backup.sh

echo ""
echo "6. Copying systemd units..."
cp "$SCRIPT_DIR"/var-mnt-tank-backups.{mount,automount} /etc/systemd/system/
cp "$SCRIPT_DIR"/restic-backup.{service,timer} /etc/systemd/system/

echo ""
echo "7. Reloading systemd daemon..."
systemctl daemon-reload

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Next steps:"
echo "  1. Configure NFS export on NAS for /mnt/tank/backups"
echo "  2. Enable automount: sudo systemctl enable --now var-mnt-tank-backups.automount"
echo "  3. Initialize repo:   sudo restic init --repo /var/mnt/tank/backups/hub-restic --password-file /etc/restic/password"
echo "  4. Enable timer:      sudo systemctl enable --now restic-backup.timer"
echo "  5. Test backup:       sudo systemctl start restic-backup.service"
echo ""

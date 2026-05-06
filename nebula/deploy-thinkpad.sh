#!/bin/bash
# Legacy/manual Nebula deploy for the ThinkPad.
# The current ThinkPad is NixOS-managed; prefer: nix run .#deploy -- think
# Use this only when intentionally installing the staging config by hand.
# Run with: sudo bash nebula/deploy-thinkpad.sh

set -euo pipefail

REPO_DIR="/home/crussell/Code/cn/nebula"
STAGING_DIR="$REPO_DIR/staging"

echo "=== Nebula ThinkPad Deployment ==="
echo ""

# 1. Copy config and certs to /etc/nebula
echo "[1/4] Installing config and certs to /etc/nebula/..."
mkdir -p /etc/nebula
cp "$STAGING_DIR/etc-nebula/config.yaml" /etc/nebula/config.yaml
cp "$STAGING_DIR/etc-nebula/ca.crt" /etc/nebula/ca.crt
cp "$STAGING_DIR/etc-nebula/host.crt" /etc/nebula/host.crt
cp "$STAGING_DIR/etc-nebula/host.key" /etc/nebula/host.key
chmod 600 /etc/nebula/host.key
chmod 640 /etc/nebula/host.crt /etc/nebula/ca.crt /etc/nebula/config.yaml
echo "  Done."

# 2. Install systemd service
echo "[2/4] Installing systemd service..."
cp "$STAGING_DIR/nebula.service" /etc/systemd/system/nebula.service
echo "  Done."

# 3. Reload and enable
echo "[3/4] Enabling and starting nebula service..."
systemctl daemon-reload
systemctl enable nebula.service
systemctl start nebula.service
echo "  Done."

# 4. Verify
echo "[4/4] Verifying..."
sleep 2

echo ""
echo "=== Service Status ==="
systemctl status nebula.service --no-pager -n 10

echo ""
echo "=== Nebula Interface ==="
ip addr show nebula0 2>/dev/null || echo "WARNING: nebula0 interface not found yet"

echo ""
echo "=== Connectivity Test ==="
echo "Pinging k2 service endpoint (10.10.0.6)..."
ping -c 3 -W 5 10.10.0.6 || echo "WARNING: Could not ping k2 service endpoint"

echo ""
echo "Pinging Hetzner lighthouse (10.10.0.2)..."
ping -c 3 -W 5 10.10.0.2 || echo "WARNING: Could not ping Hetzner lighthouse"

echo ""
echo "=== Deployment Complete ==="

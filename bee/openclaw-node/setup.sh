#!/bin/bash

# OpenClaw Node Setup Script for bee (Fedora Bluefin)
# Run this on the bee machine to set up the OpenClaw node

set -e

echo "🦞 Setting up OpenClaw Node on bee..."

# Create necessary directories
echo "Creating directories..."
mkdir -p /var/home/crussell/.openclaw-node/data
mkdir -p /var/home/crussell/.openclaw-node/workspace
mkdir -p /var/home/crussell/.config/systemd/user

# Copy service file to systemd user directory
echo "Installing systemd service..."
# Note: For user service, adjust the service file slightly
sed 's|/usr/bin/podman run|/usr/bin/podman run --userns=keep-id|' openclaw-node.service > /tmp/openclaw-node-user.service
sed -i 's|WantedBy=multi-user.target|WantedBy=default.target|' /tmp/openclaw-node-user.service
cp /tmp/openclaw-node-user.service /var/home/crussell/.config/systemd/user/openclaw-node.service

# Enable and start the service
echo "Enabling OpenClaw node service..."
loginctl enable-linger crussell
systemctl --user daemon-reload
systemctl --user enable --now openclaw-node

echo "✅ OpenClaw Node setup complete!"
echo ""
echo "Check status with: systemctl --user status openclaw-node"
echo "View logs with: journalctl --user -u openclaw-node -f"

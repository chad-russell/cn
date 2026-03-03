#!/usr/bin/env bash
# Tailscale privileged setup hook
# Runs on first boot to configure tailscale

set -euo pipefail

# Check if tailscale is already configured
if tailscale status &>/dev/null; then
    echo "Tailscale already configured"
    exit 0
fi

echo "Tailscale will need to be authenticated after first login."
echo "Run: sudo tailscale up"

# OpenClaw Node for bee (Fedora Bluefin)
# This directory contains the Podman configuration for running OpenClaw in node mode

# Setup Instructions (to be run on bee machine):
# 1. Copy this directory to bee machine (e.g., /var/home/crussell/.config/openclaw-node)
# 2. Create persistent directories:
#    mkdir -p /var/home/crussell/.openclaw-node/data
#    mkdir -p /var/home/crussell/.openclaw-node/workspace
# 3. Install the systemd service:
#    sudo cp openclaw-node.service /etc/systemd/system/
#    sudo systemctl daemon-reload
#    sudo systemctl enable --now openclaw-node
# 4. Check logs: sudo journalctl -u openclaw-node -f

# The node will connect to the gateway at ws://192.168.20.32:30086
# (Cluster VIP NodePort for openclaw-gateway service)

#!/usr/bin/env bash
set -euo pipefail

SSH_KEY="$HOME/.ssh/id_ed25519"
SSH_OPTS="-i $SSH_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
USER="crussell"
K2_IP="192.168.20.62"
K3_IP="192.168.20.63"
K4_IP="192.168.20.64"
REPO_PATH="/home/crussell/cn"

pull_node() {
    local node_ip="$1"
    local node_name="$2"
    
    echo "Pulling on $node_name ($node_ip)..."
    ssh $SSH_OPTS ${USER}@${node_ip} "cd $REPO_PATH && git pull"
    if [ $? -eq 0 ]; then
        echo "✓ $node_name updated successfully"
    else
        echo "✗ Failed to update $node_name"
        return 1
    fi
    echo
}

if [ $# -eq 0 ]; then
    echo "Pulling on all nodes (k2, k3, k4)..."
    echo "======================================="
    pull_node "$K2_IP" "k2"
    pull_node "$K3_IP" "k3"
    pull_node "$K4_IP" "k4"
    echo "======================================="
    echo "All nodes updated!"
else
    for node in "$@"; do
        case "$node" in
            k2) pull_node "$K2_IP" "k2" ;;
            k3) pull_node "$K3_IP" "k3" ;;
            k4) pull_node "$K4_IP" "k4" ;;
            *) echo "Unknown node: $node" ;;
        esac
    done
fi

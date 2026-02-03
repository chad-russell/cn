#!/usr/bin/env bash
set -euo pipefail

SSH_KEY="$HOME/.ssh/id_ed25519"
SSH_OPTS="-i $SSH_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
USER="crussell"
K2_IP="192.168.20.62"
K3_IP="192.168.20.63"
K4_IP="192.168.20.64"
REPO_PATH="/home/crussell/cn"

apply_nixos() {
    local node_ip="$1"
    local node_name="$2"
    
    echo "Applying NixOS config to $node_name ($node_ip)..."
    echo "======================================="
    ssh $SSH_OPTS ${USER}@${node_ip} "cd $REPO_PATH && sudo nixos-rebuild switch --flake .#$node_name"
    
    if [ $? -eq 0 ]; then
        echo "======================================="
        echo "✓ $node_name configuration applied successfully!"
    else
        echo "======================================="
        echo "✗ Failed to apply configuration to $node_name"
        return 1
    fi
    echo
}

if [ $# -lt 1 ]; then
    echo "Usage: $0 <node> [node...]"
    echo ""
    echo "Examples:"
    echo "  $0 k2"
    echo "  $0 k2 k3 k4"
    echo ""
    exit 1
fi

for node in "$@"; do
    case "$node" in
        k2) apply_nixos "$K2_IP" "k2" ;;
        k3) apply_nixos "$K3_IP" "k3" ;;
        k4) apply_nixos "$K4_IP" "k4" ;;
        *) echo "Unknown node: $node (valid: k2, k3, k4)" ;;
    esac
done

#!/usr/bin/env bash
set -euo pipefail

SSH_KEY="$HOME/.ssh/id_ed25519"
NAS_IP="192.168.20.31"
NAS_USER="root"
NAS_PATH="/mnt/tank/docker/beszel"
LOCAL_DIR="$HOME/Code/cn/truenas"

echo "======================================="
echo "Beszel Agent Deployment to TrueNAS"
echo "======================================="
echo ""

echo "Step 1: Copying files to TrueNAS..."
ssh -i "$SSH_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no \
  "$NAS_USER@$NAS_IP" "mkdir -p $NAS_PATH"

scp -i "$SSH_KEY" -o IdentitiesOnly=yes \
  "$LOCAL_DIR/docker-compose.yml" \
  "$NAS_USER@$NAS_IP:$NAS_PATH/"

echo "✓ Files copied successfully"
echo ""

echo "Step 2: Instructions for token setup"
echo "==================================="
echo ""
echo "1. Access https://beszel.internal.crussell.io"
echo "2. Click 'Add System'"
echo "3. Name: nas, Host: $NAS_IP, Port: 45876"
echo "4. Copy the generated TOKEN"
echo "5. Update the token in docker-compose.yml on TrueNAS:"
echo ""
echo "   ssh -i $SSH_KEY $NAS_USER@$NAS_IP"
echo "   nano $NAS_PATH/docker-compose.yml"
echo ""
echo "6. After updating, redeploy:"
echo ""
echo "   ssh -i $SSH_KEY $NAS_USER@$NAS_IP \"cd $NAS_PATH && docker compose up -d\""
echo ""
echo "======================================="
echo ""

read -p "Have you updated the token in docker-compose.yml? (y/n) " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment paused. Update token and run this script again."
    exit 0
fi

echo "Step 3: Deploying Beszel Agent..."
ssh -i "$SSH_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no \
  "$NAS_USER@$NAS_IP" "cd $NAS_PATH && docker compose up -d"

echo ""
echo "======================================="
echo "✓ Deployment complete!"
echo ""
echo "Check status:"
echo "  ssh -i $SSH_KEY $NAS_USER@$NAS_IP \"docker ps | grep beszel\""
echo ""
echo "View logs:"
echo "  ssh -i $SSH_KEY $NAS_USER@$NAS_IP \"docker logs -f beszel-agent\""
echo ""
echo "Verify in Beszel UI:"
echo "  https://beszel.internal.crussell.io"
echo "======================================="

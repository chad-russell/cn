#!/usr/bin/env bash
set -euo pipefail

SSH_KEY="$HOME/.ssh/id_ed25519"
SSH_OPTS="-i $SSH_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
USER="crussell"
K2_IP="192.168.20.62"
REPO_PATH="/home/crussell/cn/docker/swarm"
STACK_NAME="dozzle"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <stack-file> [stack-name]"
    echo ""
    echo "Examples:"
    echo "  $0 dozzle-stack.yml"
    echo "  $0 beszel-stack.yml beszel"
    echo ""
    echo "Available stacks:"
    ls -1 /home/crussell/Code/cn/docker/swarm/*.yml 2>/dev/null | xargs -n1 basename
    exit 1
fi

STACK_FILE="$1"
if [ -n "${2:-}" ]; then
    STACK_NAME="$2"
fi

if [ ! -f "$REPO_PATH/$STACK_FILE" ]; then
    echo "Error: Stack file not found: $REPO_PATH/$STACK_FILE"
    exit 1
fi

echo "Deploying $STACK_FILE as stack '$STACK_NAME'..."
echo "======================================="
ssh $SSH_OPTS ${USER}@${K2_IP} "cd $REPO_PATH && docker stack deploy -c $STACK_FILE $STACK_NAME"

if [ $? -eq 0 ]; then
    echo "======================================="
    echo "✓ Stack deployed successfully!"
    echo ""
    echo "Check status with:"
    echo "  ssh $SSH_OPTS ${USER}@${K2_IP} docker service ls | grep $STACK_NAME"
else
    echo "======================================="
    echo "✗ Deployment failed!"
    exit 1
fi

#!/bin/bash
set -e

TARGET_HOST="crussell@192.168.20.63"
TARGET_DIR="/home/crussell/docker"

echo "Deploying Docker Compose services to k3 ($TARGET_HOST)..."

# Create directories
ssh $TARGET_HOST "mkdir -p $TARGET_DIR/{onyx,beszel,n8n,searxng}"

# Copy compose files and templates
echo "Copying files..."
scp k3/docker/onyx/docker-compose.yml $TARGET_HOST:$TARGET_DIR/onyx/
scp k3/docker/onyx/env.template $TARGET_HOST:$TARGET_DIR/onyx/
scp k3/docker/beszel/docker-compose.yml $TARGET_HOST:$TARGET_DIR/beszel/
scp k3/docker/n8n/docker-compose.yml $TARGET_HOST:$TARGET_DIR/n8n/
scp k3/docker/searxng/docker-compose.yml $TARGET_HOST:$TARGET_DIR/searxng/

echo "---------------------------------------------------"
echo "Deployment files copied successfully!"
echo ""
echo "NEXT STEPS:"
echo "1. SSH into k3: ssh $TARGET_HOST"
echo "2. Go to the onyx directory: cd $TARGET_DIR/onyx"
echo "3. Create .env from template: cp env.template .env"
echo "4. Edit .env and set secure passwords: nano .env"
echo "5. Start services:"
echo "   cd $TARGET_DIR/onyx && docker compose up -d"
echo "   cd $TARGET_DIR/beszel && docker compose up -d"
echo "   cd $TARGET_DIR/n8n && docker compose up -d"
echo "   cd $TARGET_DIR/searxng && docker compose up -d"
echo ""
echo "Services will restart automatically on reboot."


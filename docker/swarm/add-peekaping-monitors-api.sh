#!/bin/bash

# Peekaping Monitor Setup via API
# Uses the REST API to add all Caddyfile services

PEEKAPING_URL="https://peekaping.internal.crussell.io/api/v1"
API_ID="b3377891-0811-4da3-95d9-147f0c333ce9"
API_KEY="pryKw3pLoYFw9uC0vGu2mezoPDSTrmViD8ljCd9iNwg="

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Peekaping API Monitor Setup ===${NC}"
echo ""

# Function to add monitor
add_monitor() {
  local name="$1"
  local url="$2"
  local type="${3:-http}"

  echo -e "${YELLOW}Adding monitor: $name${NC}"

  response=$(curl -s -X POST "$PEEKAPING_URL/monitors" \
    -H "X-API-Key-ID: $API_ID" \
    -H "X-API-Key-Secret: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"$name\",
      \"type\": \"$type\",
      \"url\": \"$url\",
      \"interval\": 30,
      \"timeout\": 10,
      \"retries\": 3,
      \"active\": true
    }")

  # Check if response contains error
  if echo "$response" | grep -q "error"; then
    echo -e "${RED}  ✗ Failed to add $name${NC}"
    echo "$response" | head -c 200
  else
    # Try to extract monitor ID
    monitor_id=$(echo "$response" | grep -oP '"id":"\K[^"]+' || echo "unknown")
    echo -e "${GREEN}  ✓ Added $name (ID: $monitor_id)${NC}"
  fi
}

# Add all monitors from Caddyfile
echo "=== Adding Internal Domain Services ==="
add_monitor "OpenClaw" "https://openclaw.internal.crussell.io"
add_monitor "Karakeep" "https://karakeep.internal.crussell.io"
add_monitor "Linkding" "https://linkding.internal.crussell.io"
add_monitor "Papra" "https://papra.internal.crussell.io"
add_monitor "Ntfy" "https://ntfy.internal.crussell.io"
add_monitor "SearXNG" "https://searxng.internal.crussell.io"
add_monitor "Dozzle" "https://dozzle.internal.crussell.io"
add_monitor "Audiobookshelf" "https://audiobookshelf.internal.crussell.io"
add_monitor "Beszel" "https://beszel.internal.crussell.io"
add_monitor "qBittorrent" "https://qbittorrent.internal.crussell.io"
add_monitor "Sonarr" "https://sonarr.internal.crussell.io"
add_monitor "Radarr" "https://radarr.internal.crussell.io"
add_monitor "Prowlarr" "https://prowlarr.internal.crussell.io"
add_monitor "Jellyseerr" "https://jellyseerr.internal.crussell.io"
add_monitor "AdGuard" "https://adguard.internal.crussell.io"

echo ""
echo "=== Adding Public Domain Services ==="
add_monitor "HomeAssistant" "https://homeassistant.crussell.io"
add_monitor "Jellyfin" "https://jellyfin.crussell.io"
add_monitor "n8n" "https://n8n.crussell.io"
add_monitor "Photos" "https://photos.crussell.io"
add_monitor "Chex Mix Timer" "https://chex-mix-timer.crussell.io"

echo ""
echo -e "${GREEN}=== Setup Complete! ===${NC}"
echo ""
echo "Verify monitors at: $PEEKAPING_URL/../monitors"
echo "Next: Configure alert channels in Peekaping UI"

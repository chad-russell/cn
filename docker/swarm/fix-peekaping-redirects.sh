#!/bin/bash

# Fix Peekaping monitors - add max_redirects support

PEEKAPING_URL="https://peekaping.internal.crussell.io/api/v1"
API_KEY="pk_eyJpZCI6IjY1N2IyZTc3LTBmYmQtNDI5Yi1hNmI4LTJkYjVmYzBmMWE1YyIsImtleSI6ImRuOFVGc0hqcGp0ZEVYaEpjN1o1VEd5QWhTUTc4RGlNaEs2MVpmdkpSTHc9In0="
NOTIFICATION_ID="f299ccf6-0ecf-40f0-9247-ec4f13604770"

# Declare associative array of services
# Format: "Monitor Name|URL"
declare -a services=(
  "Chex Mix Timer|https://chex-mix-timer.crussell.io"
  "Photos|https://photos.crussell.io"
  "n8n|https://n8n.crussell.io"
  "Jellyfin|https://jellyfin.crussell.io"
  "HomeAssistant|https://homeassistant.crussell.io"
  "AdGuard|https://adguard.internal.crussell.io"
  "Jellyseerr|https://jellyseerr.internal.crussell.io"
  "Prowlarr|https://prowlarr.internal.crussell.io"
  "Radarr|https://radarr.internal.crussell.io"
  "Sonarr|https://sonarr.internal.crussell.io"
  "qBittorrent|https://qbittorrent.internal.crussell.io"
  "Beszel|https://beszel.internal.crussell.io"
  "Audiobookshelf|https://audiobookshelf.internal.crussell.io"
  "Dozzle|https://dozzle.internal.crussell.io"
  "SearXNG|https://searxng.internal.crussell.io"
  "Ntfy|https://ntfy.internal.crussell.io"
  "Papra|https://papra.internal.crussell.io"
  "Karakeep|https://karakeep.internal.crussell.io"
  "OpenClaw|https://openclaw.internal.crussell.io"
  "Linkding|https://linkding.internal.crussell.io"
)

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Fixing Peekaping Monitors ===${NC}"
echo ""

# Function to escape URL for JSON
json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Update each service
for service in "${services[@]}"; do
  IFS='|' read -r name url <<< "$service"
  
  echo -e "${YELLOW}Updating: $name${NC}"
  
  # Build config JSON string manually to avoid escaping issues
  config="{\"url\":\"$(json_escape "$url")\",\"method\":\"GET\",\"headers\":\"{}\",\"encoding\":\"text\",\"accepted_statuscodes\":[\"2XX\",\"3XX\"],\"authMethod\":\"none\",\"max_redirects\":10}"
  
  # Get monitor ID
  monitor_id=$(curl -s "$PEEKAPING_URL/monitors?limit=100" \
    -H "X-API-Key: $API_KEY" | jq -r ".data[] | select(.name == \"$name\") | .id")
  
  if [ -z "$monitor_id" ]; then
    echo -e "${RED}  ✗ Monitor not found: $name${NC}"
    continue
  fi
  
  response=$(curl -s -X PUT "$PEEKAPING_URL/monitors/$monitor_id" \
    -H "X-API-Key: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"$name\",
      \"type\": \"http\",
      \"url\": \"$url\",
      \"interval\": 30,
      \"timeout\": 30,
      \"max_retries\": 3,
      \"retry_interval\": 30,
      \"resend_interval\": 60,
      \"notification_ids\": [\"$NOTIFICATION_ID\"],
      \"active\": true,
      \"config\": \"$config\"
    }")
  
  if echo "$response" | grep -q '"error"'; then
    echo -e "${RED}  ✗ Failed to update $name${NC}"
    echo "$response"
  else
    echo -e "${GREEN}  ✓ Updated $name${NC}"
  fi
done

echo ""
echo -e "${GREEN}=== Complete! ===${NC}"

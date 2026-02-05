#!/bin/bash

# Update all Peekaping monitors to enable redirects

PEEKAPING_URL="https://peekaping.internal.crussell.io/api/v1"
API_KEY="pk_eyJpZCI6IjY1N2IyZTc3LTBmYmQtNDI5Yi1hNmI4LTJkYjVmYzBmMWE1YyIsImtleSI6ImRuOFVGc0hqcGp0ZEVYaEpjN1o1VEd5QWhTUTc4RGlNaEs2MVpmdkpSTHc9In0="
NOTIFICATION_ID="f299ccf6-0ecf-40f0-9247-ec4f13604770"

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Updating Peekaping Monitors ===${NC}"
echo ""

# Function to update monitor
update_monitor() {
  local id="$1"
  local name="$2"
  local url="$3"
  local type="${4:-http}"

  echo -e "${YELLOW}Updating monitor: $name${NC}"

  # Build config JSON with redirects enabled
  config=$(jq -n \
    --arg url "$url" \
    '{url: $url, method: "GET", headers: "{}", encoding: "text", accepted_statuscodes: ["2XX", "3XX"], authMethod: "none", max_redirects: 10}')

  response=$(curl -s -X PUT "$PEEKAPING_URL/monitors/$id" \
    -H "X-API-Key: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"$name\",
      \"type\": \"$type\",
      \"url\": \"$url\",
      \"interval\": 30,
      \"timeout\": 30,
      \"max_retries\": 3,
      \"retry_interval\": 30,
      \"resend_interval\": 60,
      \"notification_ids\": [\"$NOTIFICATION_ID\"],
      \"active\": true,
      \"config\": $(echo "$config" | jq -sR .)
    }")

  # Check if response contains error
  if echo "$response" | grep -q '"error"'; then
    echo -e "${RED}  ✗ Failed to update $name${NC}"
    echo "$response" | head -c 200
  else
    echo -e "${GREEN}  ✓ Updated $name${NC}"
  fi
}

# Update all monitors
curl -s "$PEEKAPING_URL/monitors?limit=100" \
  -H "X-API-Key: $API_KEY" | jq -r '.data[] | "\(.id)|\(.name)|\(.url)"' | while IFS='|' read -r id name url; do
  update_monitor "$id" "$name" "$url"
done

echo ""
echo -e "${GREEN}=== Update Complete! ===${NC}"

#!/usr/bin/env bash
#
# Sync Peekaping monitors from declarative JSON configuration
#
# Usage:
#   ./sync-monitors.sh [--dry-run]
#
# Environment variables:
#   PEEKAPING_URL  - Peekaping base URL (default: https://peekaping.internal.crussell.io)
#   PEEKAPING_API_KEY - API key for authentication (required)
#
# The API key can be created in the Peekaping UI under Settings -> API Keys

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITORS_FILE="${SCRIPT_DIR}/monitors.json"

# Configuration
PEEKAPING_URL="${PEEKAPING_URL:-https://peekaping.internal.crussell.io}"
PEEKAPING_API_KEY="${PEEKAPING_API_KEY:-}"

# Check for dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "=== DRY RUN MODE - No changes will be made ==="
fi

# Validate API key
if [[ -z "$PEEKAPING_API_KEY" ]]; then
    echo "Error: PEEKAPING_API_KEY environment variable is required"
    echo "Create an API key in Peekaping UI: Settings -> API Keys"
    exit 1
fi

# Validate jq is available
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed"
    exit 1
fi

# API helper function
api_call() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    local args=(-s -X "$method")
    args+=(-H "X-API-Key: $PEEKAPING_API_KEY")
    args+=(-H "Content-Type: application/json")
    
    if [[ -n "$data" ]]; then
        args+=(-d "$data")
    fi
    
    curl "${args[@]}" "${PEEKAPING_URL}${endpoint}"
}

# Get existing monitors from API
echo "Fetching existing monitors..."
EXISTING_MONITORS=$(api_call GET "/api/v1/monitors")

if echo "$EXISTING_MONITORS" | jq -e '.data == null' &> /dev/null; then
    echo "Error: Failed to fetch monitors. Response:"
    echo "$EXISTING_MONITORS" | jq .
    exit 1
fi

# Build associative array of existing monitors by name
declare -A EXISTING_BY_NAME
declare -A EXISTING_BY_ID

while IFS= read -r monitor; do
    name=$(echo "$monitor" | jq -r '.name')
    id=$(echo "$monitor" | jq -r '.id')
    EXISTING_BY_NAME["$name"]="$id"
    EXISTING_BY_ID["$id"]="$name"
done < <(echo "$EXISTING_MONITORS" | jq -c '.data[]')

echo "Found ${#EXISTING_BY_NAME[@]} existing monitors"

# Read desired monitors from JSON
DESIRED_COUNT=$(jq '.monitors | length' "$MONITORS_FILE")
echo "Config defines $DESIRED_COUNT monitors"

# Track which monitors we've processed
declare -A PROCESSED_NAMES

# Process each monitor in the config
while IFS= read -r monitor; do
    name=$(echo "$monitor" | jq -r '.name')
    type=$(echo "$monitor" | jq -r '.type')
    config=$(echo "$monitor" | jq -c '.config')
    interval=$(echo "$monitor" | jq -r '.interval')
    timeout=$(echo "$monitor" | jq -r '.timeout')
    max_retries=$(echo "$monitor" | jq -r '.max_retries')
    retry_interval=$(echo "$monitor" | jq -r '.retry_interval')
    resend_interval=$(echo "$monitor" | jq -r '.resend_interval')
    active=$(echo "$monitor" | jq -r '.active')
    notification_ids=$(echo "$monitor" | jq -c '.notification_ids // []')
    
    PROCESSED_NAMES["$name"]=1
    
    # Build the API payload
    payload=$(jq -n \
        --arg name "$name" \
        --arg type "$type" \
        --arg config "$config" \
        --argjson interval "$interval" \
        --argjson timeout "$timeout" \
        --argjson max_retries "$max_retries" \
        --argjson retry_interval "$retry_interval" \
        --argjson resend_interval "$resend_interval" \
        --argjson active "$active" \
        --argjson notification_ids "$notification_ids" \
        '{
            name: $name,
            type: $type,
            config: $config,
            interval: $interval,
            timeout: $timeout,
            max_retries: $max_retries,
            retry_interval: $retry_interval,
            resend_interval: $resend_interval,
            active: $active,
            notification_ids: $notification_ids
        }')
    
    if [[ -n "${EXISTING_BY_NAME[$name]:-}" ]]; then
        # Monitor exists - check if update needed
        existing_id="${EXISTING_BY_NAME[$name]}"
        echo "[UPDATE] $name (id: $existing_id)"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  Would update monitor $name"
        else
            result=$(api_call PUT "/api/v1/monitors/$existing_id" "$payload")
            if echo "$result" | jq -e '.data' &> /dev/null; then
                echo "  Updated successfully"
            else
                echo "  Error updating: $(echo "$result" | jq -r '.message // .')"
            fi
        fi
    else
        # Monitor doesn't exist - create it
        echo "[CREATE] $name"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  Would create monitor $name"
        else
            result=$(api_call POST "/api/v1/monitors" "$payload")
            if echo "$result" | jq -e '.data' &> /dev/null; then
                new_id=$(echo "$result" | jq -r '.data.id')
                echo "  Created successfully (id: $new_id)"
            else
                echo "  Error creating: $(echo "$result" | jq -r '.message // .')"
            fi
        fi
    fi
done < <(jq -c '.monitors[]' "$MONITORS_FILE")

# Find monitors to delete (exist in Peekaping but not in config)
for id in "${!EXISTING_BY_ID[@]}"; do
    name="${EXISTING_BY_ID[$id]}"
    if [[ -z "${PROCESSED_NAMES[$name]:-}" ]]; then
        echo "[DELETE] $name (id: $id)"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  Would delete monitor $name"
        else
            result=$(api_call DELETE "/api/v1/monitors/$id")
            if echo "$result" | jq -e '.data' &> /dev/null || echo "$result" | jq -e '.message' | grep -qi "success\|deleted" &> /dev/null; then
                echo "  Deleted successfully"
            else
                echo "  Error deleting: $(echo "$result" | jq -r '.message // .')"
            fi
        fi
    fi
done

echo ""
echo "Sync complete!"
if [[ "$DRY_RUN" == "true" ]]; then
    echo "Run without --dry-run to apply changes"
fi

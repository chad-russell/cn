#!/bin/bash

# Peekaping Monitor Setup Script
# Sets up all Docker Swarm services for monitoring

PEEKAPING_URL="https://peekaping.internal.crussell.io"

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Peekaping Monitor Setup ===${NC}"
echo ""
echo -e "${YELLOW}Access Peekaping at: $PEEKAPING_URL${NC}"
echo ""

# Services to monitor (from Caddyfile)
declare -A SERVICES=(
  # Internal domain (*.internal.crussell.io)
  ["OpenClaw"]="https://openclaw.internal.crussell.io"
  ["Karakeep"]="https://karakeep.internal.crussell.io"
  ["Linkding"]="https://linkding.internal.crussell.io"
  ["Papra"]="https://papra.internal.crussell.io"
  ["Ntfy"]="https://ntfy.internal.crussell.io"
  ["SearXNG"]="https://searxng.internal.crussell.io"
  ["Peekaping"]="https://peekaping.internal.crussell.io"
  ["Dozzle"]="https://dozzle.internal.crussell.io"
  ["Audiobookshelf"]="https://audiobookshelf.internal.crussell.io"
  ["Beszel"]="https://beszel.internal.crussell.io"
  ["qBittorrent"]="https://qbittorrent.internal.crussell.io"
  ["Sonarr"]="https://sonarr.internal.crussell.io"
  ["Radarr"]="https://radarr.internal.crussell.io"
  ["Prowlarr"]="https://prowlarr.internal.crussell.io"
  ["Jellyseerr"]="https://jellyseerr.internal.crussell.io"
  ["AdGuard"]="https://adguard.internal.crussell.io"
  # Public domain (*.crussell.io)
  ["HomeAssistant"]="https://homeassistant.crussell.io"
  ["Jellyfin"]="https://jellyfin.crussell.io"
  ["n8n"]="https://n8n.crussell.io"
  ["Photos"]="https://photos.crussell.io"
  ["Chex Mix Timer"]="https://chex-mix-timer.crussell.io"
)

echo "=== Services to Monitor ($(echo ${#SERVICES[@]}) total) ==="
echo ""
echo "${YELLOW}Internal Domain (*.internal.crussell.io):${NC}"
echo ""
for name in "${!SERVICES[@]}"; do
  url="${SERVICES[$name]}"
  if [[ "$url" == *".internal.crussell.io"* ]]; then
    echo "  • $name: $url"
  fi
done
echo ""
echo "${YELLOW}Public Domain (*.crussell.io):${NC}"
echo ""
for name in "${!SERVICES[@]}"; do
  url="${SERVICES[$name]}"
  if [[ "$url" != *".internal.crussell.io"* ]]; then
    echo "  • $name: $url"
  fi
done
echo ""
echo -e "${YELLOW}=== Manual Setup Instructions ===${NC}"
echo ""
echo "1. Open $PEEKAPING_URL in your browser"
echo "2. Log in to Peekaping"
echo "3. Click 'Add Monitor' for each service:"
echo ""
echo "Recommended settings for all monitors:"
echo "  • Type: HTTP"
echo "  • Interval: 30 seconds"
echo "  • Timeout: 10 seconds"
echo "  • Retries: 3"
echo "  • Down threshold: 3 consecutive failures"
echo "  • Up threshold: 2 consecutive successes"
echo ""

echo -e "${YELLOW}=== Recommended Alert Channels ===${NC}"
echo ""
echo "1. Telegram:"
echo "   - Create bot: https://t.me/BotFather"
echo "   - Get bot token"
echo "   - Get your chat ID: https://t.me/userinfobot"
echo "   - Add in Peekaping: Settings → Notifications → Telegram"
echo ""
echo "2. NTFY (you host this!):"
echo "   - Server: https://ntfy.internal.crussell.io"
echo "   - Topic: peekaping-alerts (or wavy-dave)"
echo "   - Add in Peekaping: Settings → Notifications → NTFY"
echo ""

echo -e "${YELLOW}=== Check Peekaping Status ===${NC}"
curl -s -o /dev/null -w "Peekaping is up! Status: %{http_code}\n" "$PEEKAPING_URL" || echo "Peekaping is down!"

echo ""
echo -e "${GREEN}=== Setup Complete! ===${NC}"
echo "Add your monitors and alert channels through the web UI."

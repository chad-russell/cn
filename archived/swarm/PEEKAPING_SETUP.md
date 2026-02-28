# Peekaping Monitor Setup Guide

## Quick Setup via UI

Access: https://peekaping.internal.crussell.io

### Monitors to Add

| Service | Type | URL/Target | Check Interval | Description |
|---------|------|-------------|----------------|-------------|
| **Karakeep** | HTTP | https://karakeep.internal.crussell.io | 30s | Bookmark manager |
| **Immich** | HTTP | https://photos.crussell.io | 30s | Photo management |
| **SearXNG** | HTTP | https://searxng.internal.crussell.io | 30s | Privacy-focused search |
| **Papra** | HTTP | https://papra.internal.crussell.io | 30s | Habit tracker |
| **Ntfy** | HTTP | https://ntfy.internal.crussell.io | 30s | Push notifications |
| **Linkding** | HTTP | https://linkding.internal.crussell.io | 30s | Bookmark manager |

### Recommended Alert Settings

- **Down threshold**: 3 consecutive failures (retries)
- **Up threshold**: 2 consecutive successes
- **Resend interval**: 5 minutes (don't spam)

### Alert Channels to Configure

1. **Telegram** (you already have this working with OpenClaw)
   - Bot token: You'll need a bot token
   - Chat ID: Your personal chat ID

2. **NTFY** (you have ntfy.internal.crussell.io)
   - Server: https://ntfy.internal.crussell.io
   - Topic: wavy-dave (or create a new one like peekaping-alerts)

---

## API Script (when authentication is figured out)

Once Peekaping's API authentication is documented, you can use this script to bulk-add monitors.

```bash
#!/bin/bash
# Add Peekaping monitors via API

API_KEY="pk_eyJpZCI6ImIzMzc3ODkxLTA4MTEtNGRhMy05NWQ5LTE0N2YwYzMzM2NlOSIsImtleSI6InByeUt3M3BMb1lGdzl1QzB2R3UybWV6b1BEU1RybVZpRDhsakNkOWlOd2c9In0="
BASE_URL="https://peekaping.internal.crussell.io/api"

add_monitor() {
  local name="$1"
  local type="$2"
  local url="$3"

  curl -X POST "$BASE_URL/monitors" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"$name\",
      \"type\": \"$type\",
      \"url\": \"$url\",
      \"interval\": 30,
      \"timeout\": 10,
      \"retries\": 3,
      \"active\": true
    }"
}

# Add all monitors
add_monitor "Karakeep" "http" "https://karakeep.internal.crussell.io"
add_monitor "Immich" "http" "https://photos.crussell.io"
add_monitor "SearXNG" "http" "https://searxng.internal.crussell.io"
add_monitor "Papra" "http" "https://papra.internal.crussell.io"
add_monitor "Ntfy" "http" "https://ntfy.internal.crussell.io"
add_monitor "Linkding" "http" "https://linkding.internal.crussell.io"
```

---

## Docker Container Monitoring

Peekaping supports **Docker container monitoring** - this is great for checking swarm services!

To monitor a Docker container:

1. Select **Docker Container** as monitor type
2. Configure Docker daemon connection (or use Docker socket if Peekaping runs on same host)
3. Select the container to monitor (e.g., `karakeep-swarm_karakeep.1.*`)
4. Set check interval (30s recommended)

**Swarm containers to monitor via Docker:**
- `karakeep-swarm_karakeep`
- `immich-swarm_immich-server`
- `immich-swarm_immich-microservices`
- `immich-swarm_postgres`
- `immich-swarm_redis`
- `immich-swarm_machine-learning`
- `searxng_searxng`
- `papra-swarm_papra`
- `ntfy_ntfy`
- `linkding-swarm_linkding`

---

## Next Steps

1. **Set up Telegram alerts** - most reliable
2. **Add monitors** - start with HTTP endpoints
3. **Configure status page** - optional, for public visibility
4. **Test alerts** - stop a service briefly to verify notifications work

---

## Notes

- The API key provided may need to be used differently (session-based auth might be required)
- Peekaping is still in beta - API may change
- HTTP monitoring is sufficient for most use cases
- Docker container monitoring is more direct but requires Docker socket access

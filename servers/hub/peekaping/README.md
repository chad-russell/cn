# Peekaping Uptime Monitoring

[Peekaping](https://github.com/0xfurai/peekaping) is a self-hosted uptime monitoring solution. This directory contains the declarative configuration for monitoring all services in the infrastructure.

## Quick Links

- **Dashboard**: https://peekaping.internal.crussell.io
- **Documentation**: https://docs.peekaping.com
- **API Reference**: https://peekaping.internal.crussell.io/swagger/index.html

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Peekaping Container                       │
│                  (systemd-peekaping)                        │
│                                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    │
│  │  API     │  │ Producer │  │  Worker  │  │ Ingester │    │
│  │  :8383   │  │          │  │          │  │          │    │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘    │
│        │              │             │              │        │
│        └──────────────┴─────────────┴──────────────┘        │
│                              │                              │
│                    ┌─────────▼─────────┐                    │
│                    │   Redis (queue)   │                    │
│                    └───────────────────┘                    │
│                              │                              │
│                    ┌─────────▼─────────┐                    │
│                    │  SQLite (data)    │                    │
│                    │  /app/data/       │                    │
│                    └───────────────────┘                    │
└─────────────────────────────────────────────────────────────┘
```

## Declarative Configuration

Monitors are defined in `monitors.json` and synced via the `sync-monitors.sh` script.

### Adding a New Monitor

1. Edit `monitors.json` and add a new monitor entry:

```json
{
  "name": "My Service",
  "type": "http",
  "config": {
    "url": "https://myservice.internal.crussell.io",
    "method": "GET",
    "accepted_statuscodes": ["2XX"]
  },
  "interval": 30,
  "timeout": 10,
  "max_retries": 3,
  "retry_interval": 30,
  "resend_interval": 300,
  "active": true
}
```

2. Run the sync script:

```bash
# Option A: pass key inline
PEEKAPING_API_KEY="pk_xxx" ./sync-monitors.sh --dry-run  # Preview changes
PEEKAPING_API_KEY="pk_xxx" ./sync-monitors.sh            # Apply changes

# Option B: store key on disk
mkdir -p /srv/peekaping
printf 'PEEKAPING_API_KEY=pk_xxx\n' > /srv/peekaping/secrets.env
chmod 600 /srv/peekaping/secrets.env
./sync-monitors.sh --dry-run
```

### Monitor Configuration Schema

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Unique monitor name |
| `type` | string | Monitor type: `http`, `tcp`, `ping`, `dns`, `push`, `docker`, `grpc` |
| `config` | object | Type-specific configuration (JSON object) |
| `interval` | number | Check interval in seconds |
| `timeout` | number | Request timeout in seconds |
| `max_retries` | number | Consecutive failures before marking down |
| `retry_interval` | number | Seconds between retries |
| `resend_interval` | number | Seconds between alert resend (0 = no resend) |
| `active` | boolean | Whether monitoring is enabled |

### HTTP Monitor Config Options

```json
{
  "url": "https://example.com",
  "method": "GET",
  "headers": {"Authorization": "Bearer token"},
  "body": "",
  "accepted_statuscodes": ["2XX", "3XX"],
  "max_redirects": 10,
  "authMethod": "none"
}
```

## Current Monitors

### hub (192.168.20.105)

| Service | URL | Type |
|---------|-----|------|
| Linkding | https://linkding.internal.crussell.io | HTTP |
| Ntfy | https://ntfy.internal.crussell.io | HTTP |
| Papra | https://papra.internal.crussell.io | HTTP |
| Audiobookshelf | https://audiobookshelf.internal.crussell.io | HTTP |
| AdGuard | https://adguard.internal.crussell.io | HTTP |
| Immich | https://photos.crussell.io | HTTP |
| Karakeep | https://karakeep.internal.crussell.io | HTTP |
| SearXNG | https://searxng.internal.crussell.io | HTTP |
| Mastra | https://mastra.internal.crussell.io/health | HTTP |
| Mastra UI | https://mastra-ui.internal.crussell.io | HTTP |

### k1 (192.168.20.61)

| Service | URL | Type |
|---------|-----|------|
| Jellyfin | https://jellyfin.internal.crussell.io | HTTP |
| Jellyseerr | https://jellyseerr.internal.crussell.io | HTTP |
| Radarr | https://radarr.internal.crussell.io | HTTP |
| Sonarr | https://sonarr.internal.crussell.io | HTTP |
| Prowlarr | https://prowlarr.internal.crussell.io | HTTP |
| qBittorrent | https://qbittorrent.internal.crussell.io | HTTP |

### External Services

| Service | URL | Type |
|---------|-----|------|
| HomeAssistant | https://homeassistant.crussell.io | HTTP |
| Beszel | https://beszel.internal.crussell.io | HTTP |

## API Authentication

### Creating an API Key

1. Log in to the Peekaping UI
2. Go to **Settings** → **API Keys**
3. Click **Create API Key**
4. Give it a descriptive name (e.g., "sync-script")
5. Copy the key immediately (shown only once)

### Using the API Key

```bash
# Set as environment variable
export PEEKAPING_API_KEY="pk_xxx"

# Or pass directly
PEEKAPING_API_KEY="pk_xxx" ./sync-monitors.sh

# Or load from file (default path)
cat /srv/peekaping/secrets.env
```

### API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/monitors` | List all monitors |
| POST | `/api/v1/monitors` | Create monitor |
| GET | `/api/v1/monitors/{id}` | Get monitor details |
| PUT | `/api/v1/monitors/{id}` | Update monitor |
| DELETE | `/api/v1/monitors/{id}` | Delete monitor |
| GET | `/api/v1/monitors/{id}/heartbeats` | Get heartbeat history |
| GET | `/api/v1/monitors/{id}/stats/uptime` | Get uptime stats |

## Container Management

### Service Control

```bash
# View status
systemctl --user status peekaping

# Restart service
systemctl --user restart peekaping

# View logs
journalctl --user -u peekaping -f

# View container logs directly
podman logs -f systemd-peekaping
```

### Logs Analysis

```bash
# Check worker activity
podman logs systemd-peekaping 2>&1 | grep 'svc":"peekaping:worker'

# Check for errors
podman logs systemd-peekaping 2>&1 | grep -iE '(error|fail|warn)'

# Check producer scheduling
podman logs systemd-peekaping 2>&1 | grep 'Enqueued health check'
```

## Alert Channels

Alert channels are configured manually in the UI (not declarative yet).

### Ntfy (Recommended)

1. Go to **Settings** → **Notification Channels**
2. Click **Add Notification Channel**
3. Select **NTFY**
4. Configure:
   - **Name**: `ntfy-alerts`
   - **Server URL**: `https://ntfy.internal.crussell.io`
   - **Topic**: `peekaping-alerts`
5. Test and save

### Assigning to Monitors

After creating a notification channel, edit each monitor to assign the channel.

## Troubleshooting

### Queue Stuck (monitors not updating)

**Symptoms:**
- Logs show "Task already queued (duplicate prevented)"
- No worker activity in logs
- Monitor statuses don't change

**Solution:**
```bash
systemctl --user restart peekaping
```

The in-memory queue can get stuck when tasks fail and exhaust retries. A restart clears the queue state.

### All Monitors Failing with Timeouts

**Symptoms:**
- All monitors show `context deadline exceeded`
- Worker logs show connection timeouts

**Causes:**
1. Network issue between container and services
2. DNS resolution failing inside container
3. Services actually down

**Debug:**
```bash
# Test DNS resolution from container
podman exec systemd-peekaping nslookup linkding.internal.crussell.io

# Test connectivity from container
podman exec systemd-peekaping wget --spider --timeout=5 https://linkding.internal.crussell.io
```

### Authentication Errors

**Symptoms:**
- API returns "Authentication required"
- Sync script fails

**Solution:**
Ensure `PEEKAPING_API_KEY` is set correctly. Regenerate key in UI if needed.

## Quadlet Configuration

The container is defined in `../quadlets/containers/peekaping.container`:

```ini
[Unit]
Description=Peekaping Uptime Monitor

[Container]
Image=docker.io/0xfurai/peekaping-bundle-sqlite:latest
PublishPort=30087:8383
Volume=/srv/peekaping/data:/app/data
Environment=DB_NAME=/app/data/peekaping.db
Environment=TZ=America/New_York

[Service]
Restart=on-failure

[Install]
WantedBy=default.target
```

## Related Files

- `monitors.json` - Declarative monitor definitions
- `sync-monitors.sh` - Sync script to apply configuration
- `../quadlets/containers/peekaping.container` - Container definition
- `../caddy/Caddyfile` - Reverse proxy routing

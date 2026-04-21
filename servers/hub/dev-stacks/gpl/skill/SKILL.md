---
name: gpl-hosting
description: Operate the local Gloo GPL dev stack on hub. Use when working in 360-gpl, 360-hummingbird, 360-polymer, or gloo-control-plane and the task mentions starting/stopping services, logs, containers, env changes, bootstrap, or local dev infra.
---

# Gloo GPL Hosting

The Gloo dev stack runs on `hub` with infrastructure (Postgres, RustFS, pgAdmin) managed via Podman Compose and dev servers running directly on the host for native hot-reload.

## Stack Composition

| Component | Type | Port | Purpose |
|-----------|------|------|---------|
| postgres | Podman Compose | 5433 | GPL's shared Postgres database |
| rustfs | Podman Compose | 9000, 9001 | S3-compatible object storage |
| pgadmin | Podman Compose | 5050 | Database admin UI |
| gpl-app | Host (pnpm) | 3106 | GPL app (`pnpm dev`) |
| hummingbird-api | Host (pnpm) | 8000 | Hummingbird API |
| hummingbird-web | Host (pnpm) | 3100 | Hummingbird Web frontend |
| polymer-app | Host (pnpm, Node 24) | 3001 | Polymer app |

## File Locations

| File | Purpose |
|------|---------|
| `~/Code/cn/servers/hub/dev-stacks/gpl/compose.yaml` | Infra services only (postgres, rustfs, pgadmin) |
| `~/Code/cn/servers/hub/dev-stacks/gpl/host-envs/gpl.env` | Host env for GPL app |
| `~/Code/cn/servers/hub/dev-stacks/gpl/host-envs/hb-api.env` | Host env for Hummingbird API |
| `~/Code/cn/servers/hub/dev-stacks/gpl/host-envs/hb-web.env` | Host env for Hummingbird Web |
| `~/Code/cn/servers/hub/dev-stacks/gpl/host-envs/polymer.env` | Host env for Polymer |
| `~/Code/cn/servers/hub/dev-stacks/gpl/dev.sh` | Helper script to start dev servers |
| `~/Gloo/gloo-control-plane/scripts/` | Bootstrap scripts (init-buckets, etc.) |

## Start / Stop Infrastructure

```bash
COMPOSE_FILE=~/Code/cn/servers/hub/dev-stacks/gpl/compose.yaml

# Start infra (postgres, rustfs, pgadmin)
podman compose -f $COMPOSE_FILE up -d

# Stop infra
podman compose -f $COMPOSE_FILE down

# View infra logs
podman compose -f $COMPOSE_FILE logs -f
```

## Start Dev Servers on Host

```bash
# Using helper script (starts infra automatically):
~/Code/cn/servers/hub/dev-stacks/gpl/dev.sh gpl       # GPL only
~/Code/cn/servers/hub/dev-stacks/gpl/dev.sh hb-api    # Hummingbird API only
~/Code/cn/servers/hub/dev-stacks/gpl/dev.sh hb-web    # Hummingbird Web only
~/Code/cn/servers/hub/dev-stacks/gpl/dev.sh polymer   # Polymer only (uses Node 24)
~/Code/cn/servers/hub/dev-stacks/gpl/dev.sh all       # All services

# Or run manually:
cd ~/Gloo/360-gpl
env $(grep -v '^#' ~/Code/cn/servers/hub/dev-stacks/gpl/host-envs/gpl.env | xargs) pnpm dev -- -p 3106
```

**Note:** Polymer requires Node 24 (installed via Homebrew). The `dev.sh` script handles PATH setup automatically. For manual runs:
```bash
export PATH="/home/linuxbrew/.linuxbrew/opt/node@24/bin:$PATH"
```

## First-Time Bootstrap

```bash
# 1. Start infra
podman compose -f ~/Code/cn/servers/hub/dev-stacks/gpl/compose.yaml up -d

# 2. Wait for postgres health
podman exec gpl-postgres-1 pg_isready -U postgres

# 3. Create databases (if not already created)
podman exec gpl-postgres-1 psql -U postgres -c "CREATE DATABASE gpl_db;" 2>/dev/null || true
podman exec gpl-postgres-1 psql -U postgres -c "CREATE DATABASE polymer;" 2>/dev/null || true

# 4. Initialize RustFS buckets
~/Gloo/gloo-control-plane/scripts/init-buckets.sh

# 5. Install dependencies for each project
~/Gloo/gloo-control-plane/scripts/bootstrap-gpl.sh
~/Gloo/gloo-control-plane/scripts/bootstrap-hummingbird.sh
~/Gloo/gloo-control-plane/scripts/bootstrap-polymer.sh

# 6. Start dev servers
~/Code/cn/servers/hub/dev-stacks/gpl/dev.sh all
```

## Caddy Routes

Routes are defined in `~/Code/cn/servers/hub/caddy/Caddyfile`:

| Host | Service |
|------|---------|
| gpl.internal.crussell.io | gpl-app (3106) |
| hb-api.internal.crussell.io | hummingbird-api (8000) |
| hb-web.internal.crussell.io | hummingbird-web (3100) |
| polymer.internal.crussell.io | polymer-app (3001) |
| rustfs.internal.crussell.io | rustfs (9000) |
| rustfs-console.internal.crussell.io | rustfs console (9001) |
| pgadmin.internal.crussell.io | pgadmin (5050) |

After editing Caddyfile:
```bash
sudo podman cp ~/Code/cn/servers/hub/caddy/Caddyfile systemd-caddy:/etc/caddy/Caddyfile
sudo podman exec systemd-caddy caddy validate --config /etc/caddy/Caddyfile
sudo podman exec systemd-caddy caddy reload --config /etc/caddy/Caddyfile
```

## Environment Files

Host env files are in `~/Code/cn/servers/hub/dev-stacks/gpl/host-envs/`. These are derived from `~/Gloo/gloo-control-plane/envs/` but with container DNS names replaced:

| Container DNS | Host Address |
|---------------|-------------|
| `postgres:5432` | `127.0.0.1:5433` |
| `rustfs:9000` | `127.0.0.1:9000` |
| `rustfs.gloo.local` | `127.0.0.1:9000` |
| `hummingbird-api:8000` | `127.0.0.1:8000` |
| `polymer.gloo.local` | `127.0.0.1:3001` |

Browser-facing URLs (`*.internal.crussell.io`) remain unchanged — they go through Caddy.

## Volumes

Named volumes for infra persist data across restarts:
- `gpl_postgres_data` - database
- `gpl_rustfs_data`, `gpl_rustfs_logs` - object storage
- `gpl_pgadmin_data` - pgAdmin config

To wipe and start fresh:
```bash
podman compose -f ~/Code/cn/servers/hub/dev-stacks/gpl/compose.yaml down -v
```

## Troubleshooting

```bash
# Check infra container health
podman compose -f ~/Code/cn/servers/hub/dev-stacks/gpl/compose.yaml ps

# Check postgres connectivity
podman exec gpl-postgres-1 psql -U postgres -c '\l'

# Shell into postgres
podman exec -it gpl-postgres-1 psql -U postgres

# Check if a dev server port is listening
curl -s http://127.0.0.1:3106 > /dev/null && echo "GPL is up" || echo "GPL is down"

# Restart infra
podman compose -f ~/Code/cn/servers/hub/dev-stacks/gpl/compose.yaml restart
```

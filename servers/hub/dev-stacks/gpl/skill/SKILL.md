---
name: gpl-hosting
description: Operate the local Gloo GPL dev stack (Podman Compose). Use when working in 360-gpl, 360-hummingbird, 360-polymer, or gloo-control-plane and the task mentions starting/stopping services, logs, containers, env changes, bootstrap, or local dev infra.
---

# Gloo GPL Hosting

The Gloo dev stack runs on `hub` via Podman Compose. All services are defined in a single self-contained `compose.yaml`.

## Stack Composition

| Service | Image | Port | Purpose |
|---------|-------|------|---------|
| postgres | postgres:16 | 5433 | Gloo's own Postgres database |
| rustfs | rustfs/rustfs:latest | 9000, 9001 | S3-compatible object storage |
| gpl-app | gloo-node20-dev (built) | 3106 | GPL app (`pnpm dev`) |
| hummingbird-api | gloo-node20-dev (built) | 8000 | Hummingbird API |
| hummingbird-web | gloo-node20-dev (built) | 3100 | Hummingbird Web frontend |
| polymer-app | gloo-node24-dev (built) | 3001 | Polymer app |
| pgadmin | dpage/pgadmin4:8 | 5050 | Database admin UI |

## Compose File Location

```
~/Code/cn/servers/hub/dev-stacks/gpl/compose.yaml
```

## Start / Stop

```bash
COMPOSE_FILE=~/Code/cn/servers/hub/dev-stacks/gpl/compose.yaml

# Start everything
podman compose -f $COMPOSE_FILE up -d

# Start specific services only (e.g., postgres + rustfs + gpl)
podman compose -f $COMPOSE_FILE up -d postgres rustfs gpl-app

# Stop everything
podman compose -f $COMPOSE_FILE down

# Stop but keep data
podman compose -f $COMPOSE_FILE stop

# View logs
podman compose -f $COMPOSE_FILE logs -f
podman compose -f $COMPOSE_FILE logs -f gpl-app
```

## First-Time Bootstrap

```bash
# 1. Start infra services first
podman compose -f ~/Code/cn/servers/hub/dev-stacks/gpl/compose.yaml up -d postgres rustfs

# 2. Wait for postgres health
podman exec gpl-postgres-1 pg_isready -U postgres

# 3. Initialize RustFS buckets
~/Gloo/gloo-control-plane/scripts/init-buckets.sh

# 4. Bootstrap dependencies for each project
~/Gloo/gloo-control-plane/scripts/bootstrap-gpl.sh
~/Gloo/gloo-control-plane/scripts/bootstrap-hummingbird.sh
~/Gloo/gloo-control-plane/scripts/bootstrap-polymer.sh

# 5. Start app services
podman compose -f ~/Code/cn/servers/hub/dev-stacks/gpl/compose.yaml up -d
```

## Environment Files

Located at `~/Gloo/gloo-control-plane/envs/`:
- `gpl.env` - GPL app config
- `hb-api.env` - Hummingbird API config
- `hb-web.env` - Hummingbird Web config
- `polymer.env` - Polymer app config
- `pgadmin.env` - pgAdmin credentials

After editing env files, restart the affected service:
```bash
podman compose -f ~/Code/cn/servers/hub/dev-stacks/gpl/compose.yaml up -d gpl-app
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

## Source Code Mounts

Each app service mounts its source repo from the host:
- `~/Gloo/360-gpl` → gpl-app `/workspace`
- `~/Gloo/360-hummingbird` → hummingbird-api/web `/workspace`
- `~/Gloo/360-polymer` → polymer-app `/workspace`

Hot-reload works via bind mounts — changes on host are reflected immediately.

## Volumes

Named volumes persist data across restarts:
- `gpl_postgres_data` - database
- `gpl_rustfs_data`, `gpl_rustfs_logs` - object storage
- `gpl_pnpm_store` - shared pnpm cache
- `gpl_*_node_modules` - per-project node_modules
- `gpl_pgadmin_data` - pgAdmin config

To wipe and start fresh:
```bash
podman compose -f ~/Code/cn/servers/hub/dev-stacks/gpl/compose.yaml down -v
```

## Troubleshooting

```bash
# Check container health
podman ps -a --filter label=com.docker.compose.project=gpl

# Restart a single service
podman compose -f ~/Code/cn/servers/hub/dev-stacks/gpl/compose.yaml restart gpl-app

# Rebuild an image (after Containerfile changes)
podman compose -f ~/Code/cn/servers/hub/dev-stacks/gpl/compose.yaml build gpl-app

# Shell into a running container
podman exec -it gpl-app-1 bash

# Check postgres connectivity
podman exec gpl-postgres-1 psql -U postgres -c '\l'
```

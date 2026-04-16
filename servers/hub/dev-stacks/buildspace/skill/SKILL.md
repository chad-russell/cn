---
name: buildspace-hosting
description: Operate the local Buildspace dev stack on hub. Use when working in ~/Code/bs/buildspace and the task mentions starting/stopping services, database setup, bootstrap, or local dev infra.
---

# Buildspace Hosting

The Buildspace dev stack runs on `hub` with Postgres managed via Podman Compose and bun dev processes running directly on the host for native hot-reload.

## Stack Composition

| Component | Type | Port | Purpose |
|-----------|------|------|---------|
| postgres | Podman Compose | 5434 | Buildspace's own Postgres database |
| marketplace | Host (bun) | 3000 | Marketplace frontend |
| login | Host (bun) | 3003 | Auth service |
| api | Host (bun) | 3002 | API server |
| runtime | Host (bun) | 3005 | Runtime service |
| docs | Host (bun) | 3004 | Documentation site |
| super-admin | Host (bun) | 3006 | Admin panel |
| jobs | Host (bun) | 3010 | Background jobs worker |

## Compose File Location

```
~/Code/cn/servers/hub/dev-stacks/buildspace/compose.yaml
```

## Start / Stop Postgres

```bash
COMPOSE_FILE=~/Code/cn/servers/hub/dev-stacks/buildspace/compose.yaml

# Start postgres
podman compose -f $COMPOSE_FILE up -d

# Stop postgres
podman compose -f $COMPOSE_FILE down

# View logs
podman compose -f $COMPOSE_FILE logs -f
```

## First-Time Bootstrap

```bash
~/Code/cn/servers/hub/dev-stacks/buildspace/bootstrap.sh
```

This script:
1. Starts postgres via compose and waits for it to be healthy
2. Creates the database role and database from `DATABASE_URL` in `.env`
3. Enables `pgcrypto` extension
4. Runs `bun install`, migrations, and seed

## Running Dev Servers

```bash
cd ~/Code/bs/buildspace

# Start all dev servers
bun run dev

# Or start individual services:
bun --filter @buildspace/marketplace dev
bun --filter @buildspace/login dev
bun --filter @buildspace/runtime dev
bun --filter @buildspace/studio dev
bun --filter @buildspace/docs dev
bun --filter @buildspace/super-admin dev
bun --filter @buildspace/jobs-app dev
```

## Environment Files

- `~/Code/bs/buildspace/.env` - Main env file (contains `DATABASE_URL`, secrets)
- `~/Code/cn/servers/hub/dev-stacks/buildspace/.env.example` - Template

The `DATABASE_URL` in `.env` should point to the compose-managed postgres:
```
DATABASE_URL=postgresql://<user>:<pass>@127.0.0.1:5434/<dbname>
```

## Caddy Routes

Routes are defined in `~/Code/cn/servers/hub/caddy/Caddyfile`:

| Host | Service |
|------|---------|
| buildspace.internal.crussell.io | marketplace (3000) |
| bs-login.internal.crussell.io | login (3003) |
| bs-api.internal.crussell.io | api (3002) |
| bs-creator.internal.crussell.io | runtime (3005) |
| bs-docs.internal.crussell.io | docs (3004) |
| bs-admin.internal.crussell.io | super-admin (3006) |
| bs-jobs.internal.crussell.io | jobs (3010) |

After editing Caddyfile:
```bash
sudo podman cp ~/Code/cn/servers/hub/caddy/Caddyfile systemd-caddy:/etc/caddy/Caddyfile
sudo podman exec systemd-caddy caddy validate --config /etc/caddy/Caddyfile
sudo podman exec systemd-caddy caddy reload --config /etc/caddy/Caddyfile
```

## Volumes

- `buildspace_postgres_data` - database

To wipe and start fresh:
```bash
podman compose -f ~/Code/cn/servers/hub/dev-stacks/buildspace/compose.yaml down -v
```

## Troubleshooting

```bash
# Check postgres health
podman exec buildspace-postgres-1 pg_isready -U postgres

# Connect to database
podman exec -it buildspace-postgres-1 psql -U postgres

# Restart postgres
podman compose -f ~/Code/cn/servers/hub/dev-stacks/buildspace/compose.yaml restart

# Re-bootstrap database
~/Code/cn/servers/hub/dev-stacks/buildspace/bootstrap.sh
```

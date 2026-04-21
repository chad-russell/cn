---
name: buildspace-hosting
description: Operate the local Buildspace dev stack on hub. Use when working in ~/Code/bs/buildspace and the task mentions starting/stopping services, database setup, bootstrap, systemd units, or local dev infra.
---

# Buildspace Hosting

The Buildspace dev stack runs on `hub` with Postgres managed via Podman Compose and bun dev processes managed by `systemd --user`.

## Stack Composition

| Component | Type | Unit | Port | Purpose |
|-----------|------|------|------|---------|
| postgres | Podman Compose | — | 5434 | Buildspace's own Postgres database |
| marketplace | Host (bun) | `buildspace-marketplace.service` | 3000 | Marketplace frontend |
| login | Host (bun) | `buildspace-login.service` | 3003 | Auth service |
| runtime | Host (bun) | `buildspace-runtime.service` | 3002 | API server |
| studio | Host (bun) | `buildspace-studio.service` | 3005 | Creator studio |
| docs | Host (bun) | `buildspace-docs.service` | 3004 | Documentation site |
| super-admin | Host (bun) | `buildspace-super-admin.service` | 3006 | Admin panel |
| jobs | Host (bun) | `buildspace-jobs.service` | 3010 | Background jobs worker |

Target: `buildspace.target` starts all app services.

## Compose File Location

```text
~/Code/cn/servers/hub/dev-stacks/buildspace/compose.yaml
```

A `Justfile` provides the primary CLI for infra and setup. Run `just --list` in the buildspace directory.

## Infrastructure

```bash
just infra-up      # start postgres
just infra-down    # stop postgres
just infra-logs    # tail logs
```

## First-Time Bootstrap

```bash
just bootstrap
```

This script:
1. Starts postgres via compose and waits for it to be healthy
2. Creates the database role and database from `DATABASE_URL` in `.env`
3. Enables `pgcrypto` extension
4. Runs `bun install`, migrations, and seed

## App Services (systemd --user)

Install the checked-in units once on `hub`:

```bash
just install-units
```

### Individual services

```bash
systemctl --user start buildspace-marketplace.service
systemctl --user start buildspace-runtime.service
```

### All services at once

```bash
systemctl --user start buildspace.target
```

### Stop / restart

```bash
systemctl --user stop buildspace.target
systemctl --user restart buildspace-runtime.service
```

## Logs and status

This is the preferred interface for humans and AI agents.

```bash
systemctl --user status buildspace.target
journalctl --user -u buildspace-runtime.service -n 100
journalctl --user -u buildspace-marketplace.service -f
```

## Environment Files

- `~/Code/bs/buildspace/.env` - Main env file (contains `DATABASE_URL`, secrets)

The `DATABASE_URL` in `.env` should point to the compose-managed postgres:
```
DATABASE_URL=postgresql://<user>:<pass>@127.0.0.1:5434/<dbname>
```

All app services source this file before starting.

## Caddy Routes

Routes are defined in `~/Code/cn/servers/hub/caddy/Caddyfile`:

| Host | Unit | Upstream |
|------|------|----------|
| `buildspace.internal.crussell.io` | marketplace | `127.0.0.1:3000` |
| `bs-login.internal.crussell.io` | login | `127.0.0.1:3003` |
| `bs-api.internal.crussell.io` | runtime | `127.0.0.1:3002` |
| `bs-creator.internal.crussell.io` | studio | `127.0.0.1:3005` |
| `bs-docs.internal.crussell.io` | docs | `127.0.0.1:3004` |
| `bs-admin.internal.crussell.io` | super-admin | `127.0.0.1:3006` |
| `bs-jobs.internal.crussell.io` | jobs | `127.0.0.1:3010` |

## Volumes

- `buildspace_postgres_data` - database

To wipe and start fresh:
```bash
podman compose -f ~/Code/cn/servers/hub/dev-stacks/buildspace/compose.yaml down -v
```

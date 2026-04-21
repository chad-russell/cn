---
name: buildspace-hosting
description: Operate the local Buildspace dev stack on hub. Use when working in ~/Code/bs/buildspace and the task mentions starting/stopping services, database setup, bootstrap, systemd units, or local dev infra.
---

# Buildspace Hosting

The Buildspace dev stack runs on `hub` with Postgres managed via Podman Compose and bun dev processes managed by `systemd --user` (via brunch).

## Quick start

```bash
# Start everything (infra + all app services)
just -f ~/Code/cn/servers/hub/dev-stacks/buildspace/Justfile up

# Stop everything
just -f ~/Code/cn/servers/hub/dev-stacks/buildspace/Justfile stop
```

For first-time setup, use `bootstrap` instead of `up`.

## Stack Composition

| Component | Unit | Port | Purpose |
|-----------|------|------|---------|
| postgres | Compose | 5434 | Buildspace's own Postgres database |
| marketplace | `buildspace-marketplace.service` | 3000 | Marketplace frontend |
| login | `buildspace-login.service` | 3003 | Auth service |
| runtime | `buildspace-runtime.service` | 3002 | API server |
| studio | `buildspace-studio.service` | 3005 | Creator studio |
| docs | `buildspace-docs.service` | 3004 | Documentation site |
| super-admin | `buildspace-super-admin.service` | 3006 | Admin panel |
| jobs | `buildspace-jobs.service` | 3010 | Background jobs worker |

### Grouping targets

| Target | Starts |
|---|---|
| `buildspace-stack.target` | All app services + deps |
| `buildspace.target` | Umbrella over `buildspace-stack.target` |

## Compose File Location

```text
~/Code/cn/servers/hub/dev-stacks/buildspace/compose.yaml
```

A `Justfile` provides the primary CLI for infra and setup.

## Infrastructure

```bash
just -f ~/Code/cn/servers/hub/dev-stacks/buildspace/Justfile infra-up      # start postgres
just -f ~/Code/cn/servers/hub/dev-stacks/buildspace/Justfile infra-down    # stop postgres
just -f ~/Code/cn/servers/hub/dev-stacks/buildspace/Justfile infra-logs    # tail logs
```

**Important**: App services don't auto-start compose postgres. Run `just infra-up` before starting app units, or use `just up` which does both.

## First-Time Bootstrap

```bash
just -f ~/Code/cn/servers/hub/dev-stacks/buildspace/Justfile bootstrap
```

This runs the `buildspace-bootstrap.service` systemd unit, which:
1. Starts postgres via compose and waits for it to be healthy
2. Creates the database role and database from `DATABASE_URL` in `.env`
3. Enables `pgcrypto` extension
4. Runs `bun install`, migrations, and seed

Or start the unit directly:
```bash
systemctl --user start buildspace-bootstrap.service
```

## App Services (systemd --user)

Systemd user units are managed declaratively via brunch (`brunch apply ./config --target hub`).
Do **not** install or symlink unit files manually — brunch handles creation, updates, and cleanup.

### Start / stop

```bash
# All services
systemctl --user start buildspace-stack.target
systemctl --user stop buildspace-stack.target

# Individual services
systemctl --user start buildspace-runtime.service
systemctl --user restart buildspace-login.service
```

### Logs and status

```bash
systemctl --user status buildspace-stack.target
journalctl --user -u buildspace-runtime.service -n 100
journalctl --user -u buildspace-marketplace.service -f
```

## Environment

- `~/Code/bs/buildspace/.env` — Main env file (contains `DATABASE_URL` and secrets)
- `~/.config/systemd/user/buildspace-overrides.env` — Systemd `EnvironmentFile` with URL overrides for internal routing

The `DATABASE_URL` in `.env` should point to the compose-managed postgres:
```
DATABASE_URL=postgresql://<user>:<pass>@127.0.0.1:5434/<dbname>
```

Services use `bun --env-file=.env` to load the project `.env` directly.

## Caddy Routes

Routes are defined in `~/Code/cn/servers/hub/caddy/routes/internal/buildspace.caddy`:

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

- `buildspace_postgres_data` — database

To wipe and start fresh:
```bash
podman compose -f ~/Code/cn/servers/hub/dev-stacks/buildspace/compose.yaml down -v
```

# Hub Dev Stacks

Self-contained Podman Compose dev environments for `hub`. Each stack has its own postgres and is fully independent.

## Stacks

### Gloo (`gpl/`)

Gloo dev stack with infra services in Podman Compose and dev servers running on the host for native hot-reload.

**Infrastructure (Podman Compose):**
| Service | Port | Description |
|---------|------|-------------|
| postgres | 5433 | GPL's Postgres 16 |
| rustfs | 9000, 9001 | S3-compatible object storage |
| pgadmin | 5050 | Database admin UI |

**Dev Servers (Host):**
| Service | Port | Description |
|---------|------|-------------|
| gpl-app | 3106 | GPL app (`pnpm dev`) |
| hummingbird-api | 8000 | Hummingbird API |
| hummingbird-web | 3100 | Hummingbird Web |
| polymer-app | 3001 | Polymer app (requires Node 24 via Homebrew) |

**Prerequisites:**
- Repo clones at `~/Gloo/360-gpl`, `~/Gloo/360-hummingbird`, `~/Gloo/360-polymer`
- Control plane at `~/Gloo/gloo-control-plane` (contains bootstrap scripts and container env files)
- `pnpm` installed (`npm install -g --prefix ~/.local pnpm`)
- Node 24 via Homebrew (`brew install node@24`) for Polymer

**Usage:**
```bash
# Start infra only
podman compose -f servers/hub/dev-stacks/gpl/compose.yaml up -d

# Start dev servers (each in its own terminal for log visibility)
./servers/hub/dev-stacks/gpl/dev.sh gpl
./servers/hub/dev-stacks/gpl/dev.sh hb-api
./servers/hub/dev-stacks/gpl/dev.sh hb-web
./servers/hub/dev-stacks/gpl/dev.sh polymer

# Or all at once
./servers/hub/dev-stacks/gpl/dev.sh all

# Stop infra
podman compose -f servers/hub/dev-stacks/gpl/compose.yaml down
```

**Host env files** are in `gpl/host-envs/` — derived from `~/Gloo/gloo-control-plane/envs/` with container DNS names replaced by `127.0.0.1` addresses.

### Buildspace (`buildspace/`)

Buildspace dev stack with own postgres. Bun dev processes run on the host for native hot-reload.

**Prerequisites:**
- Repo clone at `~/Code/bs/buildspace`
- Env file at `~/Code/bs/buildspace/.env`
- `bun` installed on host

**Usage:**
```bash
# Bootstrap database (first time or after reset)
./servers/hub/dev-stacks/buildspace/bootstrap.sh

# Start postgres only
podman compose -f servers/hub/dev-stacks/buildspace/compose.yaml up -d

# Run dev servers on host
cd ~/Code/bs/buildspace
bun run dev
# Or individual services:
# bun --filter @buildspace/marketplace dev
# bun --filter @buildspace/login dev
# etc.

# Stop postgres
podman compose -f servers/hub/dev-stacks/buildspace/compose.yaml down
```

**Ports (host):**
| Service | Port | Route |
|---------|------|-------|
| marketplace | 3000 | buildspace.internal.crussell.io |
| login | 3003 | bs-login.internal.crussell.io |
| api | 3002 | bs-api.internal.crussell.io |
| runtime | 3005 | bs-creator.internal.crussell.io |
| docs | 3004 | bs-docs.internal.crussell.io |
| super-admin | 3006 | bs-admin.internal.crussell.io |
| jobs | 3010 | bs-jobs.internal.crussell.io |
| postgres | 5434 | internal only |

## Caddy Routes

Dev stack routes are defined directly in `servers/hub/caddy/Caddyfile`. After editing, reload:

```bash
sudo podman exec systemd-caddy caddy validate --config /etc/caddy/Caddyfile
sudo podman exec systemd-caddy caddy reload --config /etc/caddy/Caddyfile
```

## Preflight

Run before first setup to check prerequisites:

```bash
./servers/hub/dev-stacks/preflight.sh
```

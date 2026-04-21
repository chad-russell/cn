# Hub Dev Stacks

Self-contained Podman Compose dev environments for `hub`. Each stack has its own postgres and is fully independent. Dev servers run on the host for native hot-reload.

## Stacks

### Gloo (`gloo/`)

Shared infrastructure for all Gloo projects (GPL, Hummingbird, Storyhub, Polymer). Infra in Podman Compose, dev servers on the host.

**Infrastructure (Podman Compose):**
| Service | Port | Description |
|---------|------|-------------|
| postgres | 5433 | Shared Postgres (databases: `gpl_db`, `storyhub`, `polymer`) |
| rustfs | 9000, 9001 | S3-compatible object storage |
| pgadmin | 5050 | Database admin UI |

**Dev Servers (Host):**
| Service | Port | Description |
|---------|------|-------------|
| gpl | 3106 | GPL app (Next.js) |
| hb-api | 8000 | Hummingbird API (Express) |
| hb-web | 3100 | Hummingbird Web (Vite) |
| storyhub | 3007 | Storyhub (Next.js) |
| storyhub-worker | 8001 | Storyhub Worker (Hono/Bun) |
| polymer | 3001 | Polymer app (Next.js, requires Node 24) |

**Prerequisites:**
- Repo clones at `~/Gloo/360-gpl`, `~/Gloo/360-hummingbird`, `~/Gloo/360-polymer`
- `pnpm` installed (`npm install -g --prefix ~/.local pnpm`)
- Node 24 via Homebrew (`brew install node@24`) for Polymer
- Age key at `~/.config/age/key.txt` for secrets decryption

**Usage:**
```bash
# Start infra + init (first time)
podman compose -f servers/hub/dev-stacks/gloo/compose.yaml up -d
./servers/hub/dev-stacks/gloo/init-db.sh
./servers/hub/dev-stacks/gloo/init-buckets.sh

# Start dev servers (each in its own terminal)
./servers/hub/dev-stacks/gloo/dev.sh gpl
./servers/hub/dev-stacks/gloo/dev.sh hb-api
./servers/hub/dev-stacks/gloo/dev.sh hb-web
./servers/hub/dev-stacks/gloo/dev.sh storyhub
./servers/hub/dev-stacks/gloo/dev.sh storyhub-worker
./servers/hub/dev-stacks/gloo/dev.sh polymer

# Or all at once
./servers/hub/dev-stacks/gloo/dev.sh all

# Stop infra
podman compose -f servers/hub/dev-stacks/gloo/compose.yaml down
```

**Running subsets:**
```bash
# Hummingbird only (without GPL)
./servers/hub/dev-stacks/gloo/dev.sh hb-api
./servers/hub/dev-stacks/gloo/dev.sh hb-web

# Storyhub only
./servers/hub/dev-stacks/gloo/dev.sh storyhub
./servers/hub/dev-stacks/gloo/dev.sh storyhub-worker
```

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

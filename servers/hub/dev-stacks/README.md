# Hub Dev Stacks

Self-contained Podman Compose dev environments for `hub`. Each stack has its own postgres and is fully independent.

## Stacks

### Gloo (`gpl/`)

Full Gloo dev stack with own postgres, RustFS object storage, and pgAdmin.

**Services:**
| Service | Port | Description |
|---------|------|-------------|
| postgres | 5433 | Gloo's own Postgres 16 |
| rustfs | 9000, 9001 | S3-compatible object storage |
| gpl-app | 3106 | GPL app (`pnpm dev`) |
| hummingbird-api | 8000 | Hummingbird API |
| hummingbird-web | 3100 | Hummingbird Web |
| polymer-app | 3001 | Polymer app |
| pgadmin | 5050 | Database admin UI |

**Prerequisites:**
- Repo clones at `~/Gloo/360-gpl`, `~/Gloo/360-hummingbird`, `~/Gloo/360-polymer`
- Control plane at `~/Gloo/gloo-control-plane` (contains Containerfiles and env files)
- Env files at `~/Gloo/gloo-control-plane/envs/` (gpl.env, hb-api.env, hb-web.env, polymer.env, pgadmin.env)

**Usage:**
```bash
# Start the full stack
podman compose -f servers/hub/dev-stacks/gpl/compose.yaml up -d

# Follow logs
podman compose -f servers/hub/dev-stacks/gpl/compose.yaml logs -f

# Stop
podman compose -f servers/hub/dev-stacks/gpl/compose.yaml down
```

**First-time setup:**
1. Bootstrap RustFS buckets: `~/Gloo/gloo-control-plane/scripts/init-buckets.sh`
2. Bootstrap dependencies: `~/Gloo/gloo-control-plane/scripts/bootstrap-gpl.sh`, etc.
3. Update env files if DATABASE_URL references old shared postgres

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

# Hub Dev Stacks

Self-contained dev environments for `hub`.

- **Infrastructure** runs in Podman Compose
- **App dev servers** run on the host and are managed by `systemd --user`
- **Caddy** remains the shared reverse proxy

## Stacks

## Gloo (`gloo/`)

Shared infra for GPL, Hummingbird, Storyhub, and Polymer.

A `Justfile` provides the primary CLI interface. Run `just -f servers/hub/dev-stacks/gloo/Justfile --list` or `cd` into the gloo directory and run `just --list`.

### Infrastructure

| Service | Port | Notes |
|---|---:|---|
| postgres | 5433 | Shared DB host; databases: `gpl_db`, `storyhub`, `polymer` |
| rustfs | 9000 | S3-compatible API |
| rustfs console | 9001 | RustFS console |
| pgadmin | 5050 | DB UI |

Start / stop infra:

```bash
podman compose -f servers/hub/dev-stacks/gloo/compose.yaml up -d
podman compose -f servers/hub/dev-stacks/gloo/compose.yaml down
podman compose -f servers/hub/dev-stacks/gloo/compose.yaml logs -f
```

First-time infra init:

```bash
./servers/hub/dev-stacks/gloo/scripts/init-db.sh
./servers/hub/dev-stacks/gloo/scripts/init-buckets.sh
```

Schema + seed bootstrap:

```bash
./servers/hub/dev-stacks/gloo/scripts/bootstrap-data.sh
```

This script:
- stops Gloo app units
- ensures shared databases exist
- renders runtime env files
- runs GPL `db:push` + `db:seed`
- runs Hummingbird API dump restore + migrations + dev-user seed
- runs Storyhub Prisma push + seed
- runs Polymer `db:push` + `db:seed`

### App units (`systemd --user`)

| Unit / target | Purpose |
|---|---|
| `gloo-gpl.service` | GPL only |
| `gloo-hb-api.service` | Hummingbird API only |
| `gloo-hb-web.service` | Hummingbird Web only |
| `gloo-hummingbird.target` | Hummingbird API + Web |
| `gloo-storyhub.service` | Storyhub web only |
| `gloo-storyhub-worker.service` | Storyhub worker only |
| `gloo-storyhub.target` | Storyhub web + worker |
| `gloo-polymer.service` | Polymer only |
| `gloo-all.target` | All Gloo app dev services |

Install the checked-in units once on `hub`:

```bash
./servers/hub/dev-stacks/gloo/scripts/install-user-units.sh
```

Typical usage:

```bash
# Start one app
systemctl --user start gloo-gpl.service
systemctl --user start gloo-polymer.service

# Start grouped apps
systemctl --user start gloo-hummingbird.target
systemctl --user start gloo-storyhub.target
systemctl --user start gloo-all.target

# Stop / restart
systemctl --user stop gloo-polymer.service
systemctl --user restart gloo-hb-api.service
systemctl --user stop gloo-storyhub.target

# Status / logs
systemctl --user status gloo-polymer.service
journalctl --user -u gloo-polymer.service -n 100
journalctl --user -u gloo-polymer.service -f
```

### Runtime env + secrets

Per-service non-secret config lives in:

```text
servers/hub/dev-stacks/gloo/host-envs/*.env
```

Encrypted shared secrets live in:

```text
servers/hub/dev-stacks/gloo/secrets/gloo-secrets.env.age
```

On each service start, the unit runs:
1. `render-runtime-env.sh <service>`
2. Decrypts shared secrets with age
3. Writes a merged runtime env file to:
   - `/run/user/$UID/gloo/<service>.env`
4. Starts the app using that runtime env

This keeps repo files clean while still giving a predictable runtime surface.

### Project/runtime mapping

| App | Unit | Port | Runtime |
|---|---|---:|---|
| GPL | `gloo-gpl.service` | 3106 | Node 22 + pnpm |
| Hummingbird API | `gloo-hb-api.service` | 8000 | Node 22 + pnpm |
| Hummingbird Web | `gloo-hb-web.service` | 3100 | Node 22 + pnpm |
| Storyhub | `gloo-storyhub.service` | 3007 | Node 22 + pnpm |
| Storyhub Worker | `gloo-storyhub-worker.service` | 8001 | Bun |
| Polymer | `gloo-polymer.service` | 3001 | Node 24 + pnpm |

### Caddy routes

Defined in `servers/hub/caddy/Caddyfile`.

| Host | Upstream |
|---|---|
| `gpl.internal.crussell.io` | `127.0.0.1:3106` |
| `hb-api.internal.crussell.io` | `127.0.0.1:8000` |
| `hb-web.internal.crussell.io` | `127.0.0.1:3100` |
| `storyhub.internal.crussell.io` | `127.0.0.1:3007` |
| `polymer.internal.crussell.io` | `127.0.0.1:3001` |
| `rustfs.internal.crussell.io` | `127.0.0.1:9000` |
| `rustfs-console.internal.crussell.io` | `127.0.0.1:9001` |
| `pgadmin.internal.crussell.io` | `127.0.0.1:5050` |

Reload after edits:

```bash
sudo podman exec systemd-caddy caddy validate --config /etc/caddy/Caddyfile
sudo podman exec systemd-caddy caddy reload --config /etc/caddy/Caddyfile
```

### Prereqs

- `~/Gloo/360-gpl`
- `~/Gloo/360-hummingbird`
- `~/Gloo/360-polymer`
- `pnpm`
- `bun` (for `storyhub-worker`)
- Homebrew `node@24` (for Polymer)
- `age` and `~/.config/age/key.txt`
- Gloo infra running before app bootstrap (`podman compose ... up -d`)

## Buildspace (`buildspace/`)

Buildspace uses the same model as Gloo: Postgres in Podman Compose, app dev servers managed by `systemd --user`.

A `Justfile` provides the primary CLI interface. Run `just --list` in the buildspace directory.

### Infrastructure

| Service | Port | Notes |
|---|---:|---|
| postgres | 5434 | Buildspace database |

Start / stop infra:

```bash
just -f servers/hub/dev-stacks/buildspace/Justfile infra-up
just -f servers/hub/dev-stacks/buildspace/Justfile infra-down
```

First-time setup:

```bash
just -f servers/hub/dev-stacks/buildspace/Justfile bootstrap
```

### App units (`systemd --user`)

| Unit | Port | Purpose |
|---|---:|---|
| `buildspace-marketplace.service` | 3000 | Marketplace frontend |
| `buildspace-login.service` | 3003 | Auth service |
| `buildspace-runtime.service` | 3002 | API server |
| `buildspace-studio.service` | 3005 | Creator studio |
| `buildspace-docs.service` | 3004 | Documentation site |
| `buildspace-super-admin.service` | 3006 | Admin panel |
| `buildspace-jobs.service` | 3010 | Background jobs worker |
| `buildspace.target` | — | All app services |

Install the checked-in units once on `hub`:

```bash
just -f servers/hub/dev-stacks/buildspace/Justfile install-units
```

Typical usage:

```bash
systemctl --user start buildspace.target
systemctl --user stop buildspace.target
systemctl --user restart buildspace-runtime.service
systemctl --user status buildspace-marketplace.service
journalctl --user -u buildspace-runtime.service -f
```

### Environment

All services source `~/Code/bs/buildspace/.env` at startup. The `DATABASE_URL` should point to the compose-managed postgres on port 5434.

### Caddy routes

| Host | Upstream |
|---|---|
| `buildspace.internal.crussell.io` | `127.0.0.1:3000` |
| `bs-login.internal.crussell.io` | `127.0.0.1:3003` |
| `bs-api.internal.crussell.io` | `127.0.0.1:3002` |
| `bs-creator.internal.crussell.io` | `127.0.0.1:3005` |
| `bs-docs.internal.crussell.io` | `127.0.0.1:3004` |
| `bs-admin.internal.crussell.io` | `127.0.0.1:3006` |
| `bs-jobs.internal.crussell.io` | `127.0.0.1:3010` |

### Prereqs

- `~/Code/bs/buildspace`
- `bun`

## Preflight

```bash
./servers/hub/dev-stacks/preflight.sh
```

# Hub Dev Stacks

Self-contained dev environments for `hub`.

- **Infrastructure** runs in Podman Compose
- **App dev servers** run on the host and are managed by `systemd --user`
- **Caddy** remains the shared reverse proxy

## Stacks

## Gloo (`gloo/`)

Shared infra for GPL, Hummingbird, Storyhub, and Polymer.

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

First-time init:

```bash
./servers/hub/dev-stacks/gloo/init-db.sh
./servers/hub/dev-stacks/gloo/init-buckets.sh
```

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
./servers/hub/dev-stacks/gloo/install-user-units.sh
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

## Buildspace (`buildspace/`)

Buildspace keeps its current model: Postgres in Podman Compose and app processes run manually on the host.

```bash
./servers/hub/dev-stacks/buildspace/bootstrap.sh
podman compose -f servers/hub/dev-stacks/buildspace/compose.yaml up -d
cd ~/Code/bs/buildspace
bun run dev
```

## Preflight

```bash
./servers/hub/dev-stacks/preflight.sh
```

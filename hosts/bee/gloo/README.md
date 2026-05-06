# Gloo Containerized Dev Stack

The Gloo dev stack running on **bee** (`192.168.20.105` / Nebula `10.10.0.12`) inside rootless Podman containers. One container per app service, shared infra, managed via NixOS user units.

## Architecture

```
bee (192.168.20.105)
├── postgres:5433          (infra, shared by all apps)
├── rustfs:9000/9001       (infra, S3-compatible object store)
├── pgadmin:5050           (infra, database admin)
├── hb-api:8000            (Hummingbird API, Express + Prisma)
├── hb-web:3100            (Hummingbird Web, Vite React)
├── gpl:3106               (GPL, Next.js + Drizzle)
├── polymer:3001           (Polymer, Next.js + Drizzle)
├── storyhub:3007          (Storyhub, Next.js + Prisma)
└── storyhub-worker:8001   (Storyhub Worker, Bun)

k2 Caddy routes *.internal.crussell.io → bee (except Polymer, see below)
```

## Browser Access

| Service | URL | Auth |
|---------|-----|------|
| Hummingbird Web | `https://hb-web.internal.crussell.io` | Email/password (dev users) |
| Hummingbird API | `https://hb-api.internal.crussell.io` | API key |
| GPL | `https://gpl.internal.crussell.io` | Hummingbird SSO |
| Storyhub | `https://storyhub.internal.crussell.io` | Hummingbird SSO |
| Polymer | `http://localhost:3001` (via SSH tunnel) | WorkOS |
| pgAdmin | `https://pgadmin.internal.crussell.io` | `admin@example.com` / `admin` |
| RustFS Console | `https://rustfs-console.internal.crussell.io` | `rustfsadmin` / `rustfsadmin` |

### Polymer SSH Tunnel

Polymer uses WorkOS for auth, which requires `http://localhost:3001/callback` as the redirect URI. Since Polymer runs on bee, you need an SSH tunnel from your laptop:

```bash
# Start the tunnel (defined in thinkpad/home.nix)
systemctl --user start polymer-tunnel

# Open in browser
xdg-open http://localhost:3001

# Stop when done
systemctl --user stop polymer-tunnel
```

The tunnel service is defined but does **not** auto-start. It only runs when you start it manually.

## Service Management

All management happens over SSH as `crussell` on bee:

```bash
ssh bee  # or: ssh -o IdentitiesOnly=yes crussell@192.168.20.105
export XDG_RUNTIME_DIR=/run/user/$(id -u)
```

### Starting / Stopping

```bash
# Start everything from scratch
systemctl --user start gloo-c-all.target

# Start by work context
systemctl --user start gloo-c-hummingbird.target   # hb-api + hb-web
systemctl --user start gloo-c-gpl.target            # gpl (+ hb-api)
systemctl --user start gloo-c-polymer.target        # polymer
systemctl --user start gloo-c-storyhub.target       # storyhub + storyhub-worker

# Stop individual services
systemctl --user stop gloo-c-hb-web.service
systemctl --user stop gloo-c-all.target             # stop everything

# Check status
systemctl --user status 'gloo-c-*'
podman ps
```

### First-Time Setup / After Dependency Changes

Bootstrap services run `pnpm install` + `prisma generate` into the bind-mounted source repos:

```bash
systemctl --user start gloo-c-infra.target          # infra must be running first
systemctl --user start gloo-c-bootstrap-hummingbird.service
systemctl --user start gloo-c-bootstrap-gpl.service
systemctl --user start gloo-c-bootstrap-polymer.service
```

### Database Migrations & Seeding

Run via the toolbox container (has all CLI tools + compose network access):

```bash
# Hummingbird API (Prisma)
podman compose -f /etc/gloo-containerized/compose.yaml --profile tools run --rm \
  toolbox bash -c "cd /work/360-hummingbird && pnpm --filter api exec prisma db push --force-reset --skip-generate"
podman compose -f /etc/gloo-containerized/compose.yaml --profile tools run --rm \
  toolbox bash -c "cd /work/360-hummingbird && pnpm --filter api seed"

# Storyhub (Prisma)
podman compose -f /etc/gloo-containerized/compose.yaml --profile tools run --rm \
  -e DATABASE_URL="postgresql://postgres:postgres@postgres:5432/storyhub" \
  -e DIRECT_URL="postgresql://postgres:postgres@postgres:5432/storyhub" \
  toolbox bash -c "cd /work/360-hummingbird && pnpm --filter storyhub-prisma run prisma:push"
podman compose -f /etc/gloo-containerized/compose.yaml --profile tools run --rm \
  -e DATABASE_URL="postgresql://postgres:postgres@postgres:5432/storyhub" \
  -e DIRECT_URL="postgresql://postgres:postgres@postgres:5432/storyhub" \
  toolbox bash -c "cd /work/360-hummingbird && pnpm --filter storyhub-prisma exec tsx prisma/seed.ts"

# GPL (Drizzle)
podman compose -f /etc/gloo-containerized/compose.yaml --profile tools run --rm \
  -e DATABASE_URL="postgresql://postgres:postgres@postgres:5432/gpl_db" \
  toolbox bash -c "cd /work/360-gpl && pnpm run db:push"
podman compose -f /etc/gloo-containerized/compose.yaml --profile tools run --rm \
  -e DATABASE_URL="postgresql://postgres:postgres@postgres:5432/gpl_db" \
  toolbox bash -c "cd /work/360-gpl && pnpm exec tsx src/db/seed.ts"

# Polymer (Drizzle)
podman compose -f /etc/gloo-containerized/compose.yaml --profile tools run --rm \
  -e POSTGRES_URL="postgres://postgres:postgres@postgres:5432/polymer" \
  toolbox bash -c "cd /work/360-polymer && pnpm --filter @repo/db run db:push"
podman compose -f /etc/gloo-containerized/compose.yaml --profile tools run --rm \
  -e POSTGRES_URL="postgres://postgres:postgres@postgres:5432/polymer" \
  toolbox bash -c "cd /work/360-polymer/apps/polymer && pnpm run db:seed"
```

### Logs & Debugging

```bash
# Follow logs
podman logs -f gloo-hb-api-1
podman compose -f /etc/gloo-containerized/compose.yaml logs -f hb-api

# Quick health check
for port in 8000 3100 3106 3001 3007 8001; do
  printf "Port %5s: " $port
  curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:$port/
  echo
done
```

## Config Files

| File | Purpose |
|------|---------|
| `hosts/bee/gloo-containerized.nix` | NixOS module: systemd user units, targets, activation scripts |
| `hosts/bee/gloo/Containerfile` | Shared container image: Node 24 + pnpm + bun |
| `hosts/bee/gloo/compose-containerized.yaml` | Compose project: infra + bootstrap + app services + toolbox |
| `hosts/bee/gloo/envs-containerized/*.env` | Per-service env files (container DNS names) |
| `hosts/bee/configuration.nix` | `services.gloo-containerized.enable = true` |
| `secrets/gloo-secrets.env.age` | Agenix-encrypted secrets (API keys, session secrets) |
| `hosts/k2/caddy/routes/internal/gloo.caddy` | Caddy routes `*.internal.crussell.io` → bee |

## Networking

- **Container-to-container**: Uses compose service DNS names (`postgres:5432`, `hb-api:8000`, `rustfs:9000`). No Caddy hop.
- **Browser-to-service**: Routes through k2 Caddy with TLS via `*.internal.crussell.io` (Route53 DNS-01 + Let's Encrypt).
- **Polymer exception**: Uses `http://localhost:3001` via SSH tunnel because WorkOS requires `localhost` redirect URIs. The `polymer.internal.crussell.io` Caddy route still exists but is not used for the auth flow.

## Dev Credentials

| App | Users | Notes |
|-----|-------|-------|
| Hummingbird | `admin`, `sfc`, `fc`, `collaborator`, `vision`, `uploader`, `sfc2`, `reporter`, `regional` | Seeded from `api/prisma/seed.ts` |
| GPL | `admin@gpl.org` / `admin123`, `viewer@gpl.org` / `viewer123` | Seeded from `src/db/seed.ts` |
| Polymer | WorkOS SSO | Uses real WorkOS org users |
| Storyhub | Same as Hummingbird (SSO) | `storyhub` DB seeded from `storyhub-prisma/prisma/seed.ts` |

## Known Quirks

- **Prisma binary permissions**: Prisma generates engine binaries with 555 perms, which causes EACCES in rootless podman with `keep-id`. The Nix module runs a host-level `chmod -R u+w` after the Hummingbird bootstrap (`ExecStartPost`).
- **hb-api crashes on malformed JWT**: Unhandled `jwt malformed` error kills the process. The container has `restart: unless-stopped` so it recovers, but you may see brief 502s.
- **`pnpm install` needs `CI=true`**: The bootstrap commands pass `CI=true` to avoid TTY detection issues in the one-shot containers.
- **No named volumes for node_modules**: pnpm workspace symlinks break with overlay bind mounts. Source `node_modules` live directly on the bind mount.

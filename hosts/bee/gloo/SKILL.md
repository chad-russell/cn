---
name: gloo-dev
description: Develop the Gloo stack (Polymer, GPL, Hummingbird, Storyhub) on bee. Covers starting/stopping containerized services, running commands inside containers, editing env vars, updating pnpm packages, database migrations, and the full dev workflow. Load this skill when working on any Gloo project code or infrastructure on bee.
---

# Gloo Dev Stack on bee

You are running on **bee** (`192.168.20.105` / Nebula `10.10.0.12`), the dev server. The Gloo stack runs as rootless Podman containers managed by systemd user units. All source code lives at `/home/crussell/Gloo/`.

## Architecture at a Glance

```
bee (this machine)
├── Podman containers (rootless, user crussell)
│   ├── postgres:5433        (shared infra, data in named volume)
│   ├── rustfs:9000/9001     (S3-compatible object store)
│   ├── pgadmin:5050         (database admin UI)
│   ├── hb-api:8000          (Hummingbird API, Express + Prisma)
│   ├── hb-web:3100          (Hummingbird Web, Vite React)
│   ├── gpl:3106             (GPL, Next.js + Drizzle)
│   ├── polymer:3001         (Polymer, Next.js + Drizzle + WorkOS)
│   ├── storyhub:3007        (Storyhub, Next.js + Prisma)
│   └── storyhub-worker:8001 (Storyhub Worker, Bun/Hono)
│
├── ~/Gloo/                  (source repos, bind-mounted into containers)
│   ├── 360-hummingbird/     (monorepo: api/, web/, storyhub/, storyhub-worker/)
│   ├── 360-gpl/             (monorepo: GPL Next.js app)
│   └── 360-polymer/         (monorepo: apps/polymer/, apps/admin360/, packages/*)
│
├── Caddy (system service)   (TLS reverse proxy: *.dev.crussell.io → localhost:PORT)
└── AdGuardHome              (DNS: *.dev.crussell.io → 10.10.0.12)
```

**Key insight:** Source files are edited directly on disk at `~/Gloo/`. Containers bind-mount `/home/crussell/Gloo` → `/work`. Dev servers (Next.js, Vite, Express) watch for file changes and hot-reload. You edit files on the host; the container picks up changes automatically.

**Important:** The `pnpm store` lives in a Podman named volume (`gloo_pnpm_store`), NOT on the host filesystem. Running `pnpm install` on the host will NOT work. All package operations must run inside a container.

## Service Management

All services are **systemd user units** running as `crussell`. You need `XDG_RUNTIME_DIR` set (it should already be set in your shell, but if not: `export XDG_RUNTIME_DIR=/run/user/$(id -u)`).

### Starting Services

```bash
# Start everything (infra + all apps)
systemctl --user start gloo-c-all.target

# Start by work context
systemctl --user start gloo-c-infra.target          # postgres + rustfs + pgadmin
systemctl --user start gloo-c-hummingbird.target     # hb-api + hb-web (needs infra)
systemctl --user start gloo-c-gpl.target             # gpl (+ hb-api dependency)
systemctl --user start gloo-c-polymer.target         # polymer
systemctl --user start gloo-c-storyhub.target        # storyhub + storyhub-worker

# Order matters: infra must be up before apps
systemctl --user start gloo-c-infra.target && sleep 5 && systemctl --user start gloo-c-polymer.target
```

### Stopping Services

```bash
systemctl --user stop gloo-c-polymer.service         # stop one service
systemctl --user stop gloo-c-all.target               # stop all apps (infra keeps running)
systemctl --user stop gloo-c-infra.target             # stop infra too
```

### Restarting a Single Service

```bash
# For app services: just restart the unit (compose handles the container lifecycle)
systemctl --user restart gloo-c-polymer.service

# If the container is in a bad state, stop the unit, remove the container, start fresh:
systemctl --user stop gloo-c-polymer.service
podman rm -f gloo-polymer-1 2>/dev/null
systemctl --user start gloo-c-polymer.service
```

### Checking Status

```bash
systemctl --user status 'gloo-c-*'         # all gloo units
systemctl --user status gloo-c-polymer      # one service
podman ps                                   # running containers
```

### Viewing Logs

```bash
# Via systemd (includes restart history)
journalctl --user -u gloo-c-polymer -f      # follow
journalctl --user -u gloo-c-polymer --no-pager -n 50  # last 50 lines

# Via podman (raw container stdout)
podman logs -f gloo-polymer-1               # follow
podman logs --tail 50 gloo-polymer-1        # last 50 lines
```

## Running Commands Inside Containers

This is the core of the dev workflow. You cannot run `pnpm`, `npx`, `node`, etc. on the host. Use the compose project to run commands inside the container environment.

### The Compose File

The compose project lives at `/etc/gloo-containerized/compose.yaml`. All compose commands reference it:

```bash
COMPOSE="podman compose -f /etc/gloo-containerized/compose.yaml"
```

### The Toolbox Container

The `toolbox` service is a persistent shell in the compose network with all tools (Node, pnpm, bun, git) and access to all source repos. It's in the `tools` profile so it doesn't auto-start.

```bash
# Run a one-off command via toolbox
$COMPOSE --profile tools run --rm toolbox bash -c "cd /work/360-polymer && pnpm check-types"

# Run an interactive shell (add -it if you need TTY)
$COMPOSE --profile tools run --rm toolbox bash

# With custom env vars
$COMPOSE --profile tools run --rm \
  -e POSTGRES_URL="postgres://postgres:postgres@postgres:5432/polymer" \
  toolbox bash -c "cd /work/360-polymer && pnpm --filter @repo/db run db:push"
```

### Running Commands for a Specific App

You can also use the app's own container service to run commands:

```bash
# Run pnpm check-types in the polymer container context
$COMPOSE run --rm --no-deps polymer bash -c "cd /work/360-polymer && pnpm check-types"

# Run a build
$COMPOSE run --rm --no-deps polymer bash -c "cd /work/360-polymer && pnpm build"
```

**Note:** `--no-deps` skips starting dependencies (postgres, etc.) which is fine for type-checking and linting but NOT for commands that need database access.

### Container DNS Names

Inside the compose network, services reach each other by compose service name:

| Service | DNS Name | Port |
|---------|----------|------|
| PostgreSQL | `postgres` | `5432` |
| RustFS (S3) | `rustfs` | `9000` |
| Hummingbird API | `hb-api` | `8000` |
| Hummingbird Web | `hb-web` | `3100` |
| GPL | `gpl` | `3106` |
| Polymer | `polymer` | `3001` |
| Storyhub | `storyhub` | `3007` |
| Storyhub Worker | `storyhub-worker` | `8001` |

The toolbox container can use these DNS names directly. That's why env files say `postgres:5432` not `localhost:5433`.

## Common Dev Workflows

### Editing Source Code

1. Edit files directly in `~/Gloo/<repo>/` on the host (that's what you're doing when you use this agent).
2. The running container bind-mounts the source, so Next.js/Vite/Express dev servers will hot-reload automatically.
3. If hot-reload doesn't pick up a change (e.g., you changed an env var or a config file), restart the service unit.

### Updating pnpm Packages

You cannot run `pnpm add` on the host. Use the toolbox or the bootstrap services:

**For a quick package add (e.g., adding a npm package to polymer):**
```bash
# Run pnpm add inside the container
podman compose -f /etc/gloo-containerized/compose.yaml --profile tools run --rm \
  toolbox bash -c "cd /work/360-polymer && pnpm add <package-name> --filter polymer"
```

**For a full reinstall (e.g., after switching branches with different lockfiles):**
```bash
# Re-run the bootstrap service for the relevant project
systemctl --user restart gloo-c-bootstrap-polymer.service

# Watch progress
journalctl --user -u gloo-c-bootstrap-polymer -f
```

**The bootstrap services** run `pnpm install` + any code generation (Prisma generate, etc.) into the bind-mounted source. They also share the `pnpm_store` named volume so packages are cached across runs.

### Editing Environment Variables

Env vars come from **three sources**, in order of preference:

1. **Per-service env files** at `/etc/gloo-containerized/envs-containerized/<service>.env` — these are the non-secret config. **These are installed by NixOS from the repo at `hosts/bee/gloo/envs-containerized/*.env`.** To change them:
   - Edit the source file in the repo: `hosts/bee/gloo/envs-containerized/<service>.env`
   - Deploy bee: `nix run .#deploy -- bee` (from the infra repo on thinkpad)
   - Restart the service: `systemctl --user restart gloo-c-<service>.service`

2. **Agenix-encrypted secrets** at `/run/agenix/gloo-secrets` — API keys, session secrets, etc. To change a secret:
   - Edit `secrets/gloo-secrets.env.age` in the infra repo
   - Deploy bee: `nix run .#deploy -- bee`
   - Restart the relevant service(s)

3. **Compose-level env vars** — set in `compose-containerized.yaml` (rarely used directly).

**Quick-and-dirty env var testing:** You can pass env vars directly via the toolbox without editing files:
```bash
podman compose -f /etc/gloo-containerized/compose.yaml --profile tools run --rm \
  -e SOME_VAR=some_value \
  toolbox bash -c "cd /work/360-polymer && pnpm --filter polymer dev"
```

But for persistent changes, always update the env files in the repo and deploy.

### Database Migrations & Schema Changes

Run these via the toolbox container. The database is accessible at `postgres:5432` from inside the compose network.

**Polymer (Drizzle ORM):**
```bash
# Push schema changes (dev mode — no migration files)
podman compose -f /etc/gloo-containerized/compose.yaml --profile tools run --rm \
  -e POSTGRES_URL="postgres://postgres:postgres@postgres:5432/polymer" \
  toolbox bash -c "cd /work/360-polymer && pnpm --filter @repo/db run db:push"

# Seed the database
podman compose -f /etc/gloo-containerized/compose.yaml --profile tools run --rm \
  -e POSTGRES_URL="postgres://postgres:postgres@postgres:5432/polymer" \
  toolbox bash -c "cd /work/360-polymer/apps/polymer && pnpm run db:seed"

# Generate migration files (if using migrations instead of push)
podman compose -f /etc/gloo-containerized/compose.yaml --profile tools run --rm \
  -e POSTGRES_URL="postgres://postgres:postgres@postgres:5432/polymer" \
  toolbox bash -c "cd /work/360-polymer && pnpm --filter @repo/db run db:generate"
```

**Hummingbird (Prisma):**
```bash
# Push schema + force reset
podman compose -f /etc/gloo-containerized/compose.yaml --profile tools run --rm \
  toolbox bash -c "cd /work/360-hummingbird && pnpm --filter api exec prisma db push --force-reset --skip-generate"

# Seed
podman compose -f /etc/gloo-containerized/compose.yaml --profile tools run --rm \
  toolbox bash -c "cd /work/360-hummingbird && pnpm --filter api seed"
```

**GPL (Drizzle):**
```bash
# Push schema
podman compose -f /etc/gloo-containerized/compose.yaml --profile tools run --rm \
  -e DATABASE_URL="postgresql://postgres:postgres@postgres:5432/gpl_db" \
  toolbox bash -c "cd /work/360-gpl && pnpm run db:push"

# Seed
podman compose -f /etc/gloo-containerized/compose.yaml --profile tools run --rm \
  -e DATABASE_URL="postgresql://postgres:postgres@postgres:5432/gpl_db" \
  toolbox bash -c "cd /work/360-gpl && pnpm exec tsx src/db/seed.ts"
```

**Storyhub (Prisma):**
```bash
# Push schema
podman compose -f /etc/gloo-containerized/compose.yaml --profile tools run --rm \
  -e DATABASE_URL="postgresql://postgres:postgres@postgres:5432/storyhub" \
  -e DIRECT_URL="postgresql://postgres:postgres@postgres:5432/storyhub" \
  toolbox bash -c "cd /work/360-hummingbird && pnpm --filter storyhub-prisma run prisma:push"

# Seed
podman compose -f /etc/gloo-containerized/compose.yaml --profile tools run --rm \
  -e DATABASE_URL="postgresql://postgres:postgres@postgres:5432/storyhub" \
  -e DIRECT_URL="postgresql://postgres:postgres@postgres:5432/storyhub" \
  toolbox bash -c "cd /work/360-hummingbird && pnpm --filter storyhub-prisma exec tsx prisma/seed.ts"
```

### Direct Database Access

```bash
# psql via the postgres container (from host, port 5433)
podman exec -it gloo-postgres-1 psql -U postgres -d polymer

# Or from inside the compose network (e.g., via toolbox)
$COMPOSE --profile tools run --rm toolbox bash -c "psql -h postgres -U postgres -d polymer"

# pgAdmin web UI: https://pgadmin.dev.crussell.io (admin@example.com / admin)
```

### Linting, Formatting, Type Checking

These run inside containers. The source files are on the host bind mount, so changes are immediate.

```bash
# Polymer
$COMPOSE --profile tools run --rm toolbox bash -c "cd /work/360-polymer && pnpm lint"
$COMPOSE --profile tools run --rm toolbox bash -c "cd /work/360-polymer && pnpm format"
$COMPOSE --profile tools run --rm toolbox bash -c "cd /work/360-polymer && pnpm check-types"

# Hummingbird
$COMPOSE --profile tools run --rm toolbox bash -c "cd /work/360-hummingbird && pnpm run lint:all"

# GPL
$COMPOSE --profile tools run --rm toolbox bash -c "cd /work/360-gpl && pnpm lint"
```

**Tip:** You can skip `--profile tools` and use a specific service container with `--no-deps` for faster startup if you just need linting/type-checking (no DB needed):

```bash
$COMPOSE run --rm --no-deps polymer bash -c "cd /work/360-polymer && pnpm check-types"
```

### Building

```bash
# Build a specific app
$COMPOSE --profile tools run --rm toolbox bash -c "cd /work/360-polymer && pnpm build"

# Build a specific app with turbo filter
$COMPOSE --profile tools run --rm toolbox bash -c "cd /work/360-polymer && pnpm --filter polymer build"
```

## Project-Specific Notes

### Polymer (`~/Gloo/360-polymer/`)

- **Monorepo**: pnpm + Turborepo. Apps: `apps/polymer` (main), `apps/admin360` (admin panel). Packages: `packages/ui`, `packages/db`, `packages/auth`, `packages/reports`, `packages/typescript-config`.
- **ORM**: Drizzle. Schema in `packages/db/` and `apps/polymer/lib/db/`.
- **Auth**: WorkOS (AuthKit). Requires `http://localhost:3001/callback` as redirect URI — users access via SSH tunnel from their laptop.
- **Dev server port**: 3001. Runs with `--turbo` (Turbopack).
- **Working dir in container**: `/work/360-polymer/apps/polymer` (the dev server starts here).
- **Container unit**: `gloo-c-polymer.service`.
- **Env file**: `/etc/gloo-containerized/envs-containerized/polymer.env`.
- **Database**: `polymer` on the shared postgres.
- **S3 bucket**: `polymer-bucket` on RustFS.

### GPL (`~/Gloo/360-gpl/`)

- **Monorepo**: Single Next.js app with Drizzle ORM.
- **Auth**: Better Auth with Hummingbird SSO.
- **Dev server port**: 3106.
- **Container unit**: `gloo-c-gpl.service`.
- **Depends on**: `hb-api` (for SSO and API calls).
- **Database**: `gpl_db` on shared postgres.

### Hummingbird (`~/Gloo/360-hummingbird/`)

- **Monorepo**: pnpm + Turborepo. Packages: `api/` (Express + Prisma), `web/` (Vite React), `storyhub/` (Next.js), `storyhub-worker/` (Bun/Hono), `storyhub-prisma/` (shared Prisma schema).
- **Ports**: API 8000, Web 3100, Storyhub 3007, Worker 8001.
- **Container units**: `gloo-c-hb-api`, `gloo-c-hb-web`, `gloo-c-storyhub`, `gloo-c-storyhub-worker`.
- **Database**: `postgres` (default) for API, `storyhub` for Storyhub services.

## Known Quirks

1. **Prisma binary permissions**: Prisma generates engine binaries with `555` perms, causing EACCES in rootless Podman with `keep-id`. The Nix module runs `chmod -R u+w` after Hummingbird bootstrap. If you see permission errors in `generated/` dirs, run: `chmod -R u+w ~/Gloo/360-hummingbird/api/generated ~/Gloo/360-hummingbird/storyhub-prisma/generated ~/Gloo/360-hummingbird/storyhub/generated`

2. **hb-api crashes on malformed JWT**: Unhandled `jwt malformed` error kills the process. The container has `restart: unless-stopped` so it recovers, but you may see brief 502s. Just wait a few seconds.

3. **`pnpm install` needs `CI=true`**: The bootstrap commands pass `CI=true` to avoid TTY detection issues. If running `pnpm install` manually via toolbox, add `CI=true` if it hangs.

4. **No named volumes for node_modules**: pnpm workspace symlinks break with overlay bind mounts. Source `node_modules` live directly on the bind mount at `~/Gloo/<repo>/node_modules/`.

5. **Container names follow compose convention**: `gloo-<service>-1` (e.g., `gloo-polymer-1`, `gloo-hb-api-1`). The `1` suffix is Podman/compose convention.

6. **`pnpm store` is a named volume**: It persists across container rebuilds but is NOT visible on the host filesystem. Don't try to inspect or modify it directly.

7. **Polymer uses `--turbo` flag**: The dev server runs with Turbopack. If you see Turbopack-specific issues, you can switch to webpack by editing the compose command, but this requires a deploy.

## Quick Reference: URLs

| Service | URL | Notes |
|---------|-----|-------|
| Polymer | `http://localhost:3001` (via SSH tunnel) | WorkOS requires localhost redirect |
| GPL | `https://gpl.dev.crussell.io` | Hummingbird SSO |
| Hummingbird Web | `https://hb-web.dev.crussell.io` | Email/password dev users |
| Hummingbird API | `https://hb-api.dev.crussell.io` | API key |
| Storyhub | `https://storyhub.dev.crussell.io` | Hummingbird SSO |
| pgAdmin | `https://pgadmin.dev.crussell.io` | `admin@example.com` / `admin` |
| RustFS Console | `https://rustfs-console.dev.crussell.io` | `rustfsadmin` / `rustfsadmin` |

## Quick Reference: Nix Config Files

These files control the infrastructure. Changes require a deploy (`nix run .#deploy -- bee` from the infra repo on thinkpad):

| File | What it controls |
|------|-----------------|
| `hosts/bee/gloo-containerized.nix` | systemd user units, activation scripts |
| `hosts/bee/gloo/compose-containerized.yaml` | compose services, volumes, networks |
| `hosts/bee/gloo/Containerfile` | shared container image (Node 24 + pnpm + bun) |
| `hosts/bee/gloo/envs-containerized/*.env` | per-service env files (installed to `/etc/gloo-containerized/`) |
| `hosts/bee/caddy-dev.nix` | Caddy reverse proxy routes (`*.dev.crussell.io`) |
| `hosts/bee/adguardhome.nix` | DNS rewrites for `*.dev.crussell.io` |
| `secrets/gloo-secrets.env.age` | encrypted secrets (agenix) |
| `hosts/bee/configuration.nix` | enables `services.gloo-containerized` |

## Quick Reference: Dev Credentials

| App | Users | Notes |
|-----|-------|-------|
| Hummingbird | `admin`, `sfc`, `fc`, `collaborator`, `vision`, `uploader`, `sfc2`, `reporter`, `regional` | Seeded from `api/prisma/seed.ts` |
| GPL | `admin@gpl.org` / `admin123`, `viewer@gpl.org` / `viewer123` | Seeded from `src/db/seed.ts` |
| Polymer | WorkOS SSO | Uses real WorkOS org users |
| Storyhub | Same as Hummingbird (SSO) | Seeded from `storyhub-prisma/prisma/seed.ts` |
| PostgreSQL | `postgres` / `postgres` | Superuser, port 5433 from host |
| pgAdmin | `admin@example.com` / `admin` | Web UI |
| RustFS | `rustfsadmin` / `rustfsadmin` | S3-compatible console |

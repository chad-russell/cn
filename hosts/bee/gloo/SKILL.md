---
name: gloo-dev
description: Develop the Gloo stack using devcontainers on bee. Covers running commands, starting dev servers, managing containers, and the full dev workflow. Load this skill when working on any Gloo project code or when interacting with the devcontainer infrastructure on bee.
---

# Gloo Dev Workflow on bee

You are working on **bee** (`10.10.0.12`). Gloo products run inside **devcontainers** — one per repo. All app commands go through `glooctl`. Never run `pnpm`, `npm`, `node`, or any dev tool directly on the host.

## Architecture

```
bee (10.10.0.12)
└── Per-repo devcontainers (podman + docker-compose)
    ├── polymer      ~/Gloo/360-polymer      ports 3000, 3001
    ├── gpl          ~/Gloo/360-gpl          port 3006
    ├── hummingbird  ~/Gloo/360-hummingbird  ports 8000 (API), 3000 (web)
    └── storyhub     ~/Gloo/360-hummingbird  port 3001 (shares devcontainer with hummingbird)
```

Hummingbird and storyhub share the same devcontainer (same repo, same compose project `gloo-hb`). They have separate dev servers (separate systemd units). Both can run simultaneously.

## The Golden Rule

**ALL app commands run inside the devcontainer via `glooctl`.** Source files are bind-mounted (`../:/workspace`), so edits on the host are immediately reflected inside the container.

```bash
# CORRECT
glooctl exec polymer -- pnpm install
glooctl start hummingbird
glooctl exec hummingbird -- pnpm --filter api exec prisma generate

# WRONG — never do this on the host
pnpm install
npm run dev
node -e "..."
```

## glooctl Reference

```bash
glooctl up <product>                # Build + start devcontainer, run setup
glooctl down <product>              # Stop devcontainer (warns if sibling running)
glooctl down --force <product>      # Stop devcontainer + sibling dev servers
glooctl setup <product>             # Re-run postCreateCommand
glooctl shell <product>             # Interactive shell in devcontainer
glooctl exec <product> -- <cmd>     # Run one command
glooctl start <product> [-- <cmd>]  # Start dev server (detached, default: pnpm dev)
glooctl stop <product>              # Stop dev server
glooctl restart <product>           # Restart dev server
glooctl logs <product> [-f]         # View dev server logs (journalctl)
glooctl status [product]            # Show what's running
```

Products: `polymer`, `gpl`, `hummingbird`, `storyhub`

## Typical Session

```bash
ssh -o IdentitiesOnly=yes crussell@10.10.0.12

# First time or after down:
glooctl up hummingbird

# Start the dev server (runs detached under systemd, no blocking TUI)
glooctl start hummingbird

# Follow logs
glooctl logs hummingbird -f

# Stop when done
glooctl stop hummingbird

# Tear down the devcontainer entirely
glooctl down hummingbird
```

## How glooctl Works

- `glooctl up` runs `docker-compose up -d --build` with the repo's `.devcontainer/docker-compose.yml` plus a port publishing override from `~/.config/gloo/overrides/`.
- `glooctl start` runs the dev server as a **systemd user transient unit** via `docker-compose exec -T`. No blocking TUI — Turbo detects no TTY and outputs plain text. `yes` is piped into the setup command for non-interactive prompts.
- `glooctl exec` uses `docker-compose exec -T` (no TTY allocation) so it works from agents and scripts.
- Logs go to `journalctl --user -u gloo-<product>`.
- Source is bind-mounted (`../:/workspace`), so host edits reflect instantly.
- The override files add `userns_mode: "keep-id"` to fix rootless podman UID mapping — without this, the `node` user inside the container can't write to bind-mounted host directories.

## Shared Devcontainers

Hummingbird and storyhub share the same compose project (`gloo-hb`). This means:

- `glooctl up hummingbird` and `glooctl up storyhub` both start the same containers. Running either is idempotent.
- `glooctl start hummingbird` and `glooctl start storyhub` create separate systemd units. Both can run simultaneously.
- `glooctl down hummingbird` will **warn** if the storyhub dev server is still running. Use `glooctl down --force` to tear down anyway.
- `glooctl down storyhub` likewise warns if hummingbird is running.

## Editing Code

Edit files normally on the host. Changes take effect immediately inside the devcontainer. After editing `package.json` or any dependency file, run:

```bash
glooctl exec polymer -- pnpm install
```

## Environment Variables

Each repo uses `.env` / `.env.local` files (gitignored, backed by 1Password). They live inside the repo directory on the host and are bind-mounted into the devcontainer. They are **NOT** managed by Nix or agenix.

- `glooctl up` runs the repo's `.devcontainer/scripts/setup-env.sh` which copies devcontainer-specific env templates into place (e.g., `api/.env`, `storyhub/.env`). These point to the devcontainer's own services (`db_hb:5432`, `polymer_db:5432`, `minio:9000`).
- Some repos have multiple `.env.local` files (e.g., polymer has `apps/polymer/.env.local`, `packages/db/.env.local`, root `.env.local`). All must point to devcontainer services, not `127.0.0.1`.
- If env vars need overriding for a specific command, pass them inline:

```bash
glooctl exec polymer -- DATABASE_URL="postgres://..." pnpm db:push
```

## Dev Server Management

`glooctl start` runs the dev server as a systemd user unit:
- **Detached** — no blocking TUI, safe for agents
- Logs: `glooctl logs <product> -f` or `journalctl --user -u gloo-<product> -f`
- Status: `glooctl status`
- If a dev server crashes, check logs for the specific product, not the container

## Adding NPM Packages

```bash
glooctl exec polymer -- pnpm add some-package
glooctl exec hummingbird -- pnpm add some-package
```

## Database Operations

Each devcontainer has its own postgres. Connection details are in the repo's env files (set by `setup-env.sh`).

**Polymer** (Drizzle):
```bash
glooctl exec polymer -- pnpm db:push          # push schema
glooctl exec polymer -- pnpm db:seed           # seed data
```

**Hummingbird API** (Prisma):
```bash
glooctl exec hummingbird -- pnpm --filter api exec prisma generate
glooctl exec hummingbird -- pnpm --filter api exec prisma db push --force-reset --skip-generate
glooctl exec hummingbird -- pnpm --filter api seed
```

**Storyhub** (Prisma):
```bash
glooctl exec storyhub -- pnpm run seed:storyhub
```

**GPL** (Drizzle):
```bash
glooctl exec gpl -- pnpm run db:push
```

## Linting / Type Checking / Building

```bash
glooctl exec polymer -- pnpm lint
glooctl exec polymer -- pnpm check-types
glooctl exec polymer -- pnpm build
glooctl exec hummingbird -- pnpm run lint:all
glooctl exec gpl -- pnpm lint
```

## Product Details

### Polymer (`~/Gloo/360-polymer/`)
- **Monorepo**: pnpm + Turborepo. `pnpm dev` runs `turbo run dev` which starts:
  - `polymer` (`next dev --turbo`) → port **3000**
  - `admin360` (`next dev --turbo --port 3001`) → port **3001**
  - `@repo/db#db:studio` (Drizzle Studio, internal)
- **ORM**: Drizzle. Schema in `packages/db/`.
- **Auth**: WorkOS (AuthKit). Redirect URI: `http://localhost:3000/callback`.
- **Database**: `polymer_db` in devcontainer (postgres 16, host port 54324).
- **Object storage**: `polymer_minio` in devcontainer (host ports 9004/9005).
- **Env files**: `apps/polymer/.env.local`, `packages/db/.env.local`, root `.env.local`. All three must have correct `POSTGRES_URL`.
- **Override**: `~/.config/gloo/overrides/polymer.yml` publishes ports 3000, 3001 and fixes rootless podman UID mapping.

### GPL (`~/Gloo/360-gpl/`)
- **Single Next.js app** with Drizzle ORM.
- **Auth**: Better Auth with Hummingbird SSO. **Requires hummingbird API running** for login.
- **Dev server**: port 3006.
- **Database**: `db` in devcontainer (postgres 15, host port 5432).
- **Object storage**: `minio` in devcontainer (host ports 9000/9001).
- **Override**: `~/.config/gloo/overrides/gpl.yml` fixes rootless podman UID mapping. Port 3006 already published in devcontainer compose.

### Hummingbird (`~/Gloo/360-hummingbird/`)
- **Dev command**: `pnpm devcontainer:hb` = `turbo dev --filter api --filter web`
- **Packages**:
  - `api/` — Express + Prisma, `tsx watch server` → port **8000**
  - `web/` — Vite React → port **3000**
- **Database**: `db_hb` in devcontainer (postgres 16, host port 5567). Env: `api/.env` with `CONN_URL=postgresql://postgres:postgres@db_hb:5432/postgres`.
- **Minio**: defined in compose but behind `minio` profile — **not started by default**. S3 features won't work unless started manually: `docker-compose --project-name gloo-hb -f ... -f ... up -d minio`.
- **storyhub-worker**: separate compose service with its own Dockerfile, port **8001**, always runs when the devcontainer is up.
- **Env files**: `api/.env`, `storyhub/.env`, `storyhub-worker/.env`, `storyhub-prisma/.env` — all created by `setup-env.sh` from `.devcontainer/envs/*.env.devcontainer` templates.
- **Override**: `~/.config/gloo/overrides/hb.yml` publishes ports 8000, 3000, 3001 and fixes rootless podman UID mapping.
- **Login credentials**: `admin`, `sfc`, `fc`, `collaborator`, `vision`, `uploader`, `sfc2`, `reporter`, `regional`.

### Storyhub (same repo as hummingbird)
- **Dev command**: `pnpm devcontainer:storyhub` = `turbo dev --filter storyhub`
- **App**: Next.js (`next dev --port 3001`) → port **3001**
- **Database**: `db_storyhub` in devcontainer (postgres 16, host port 54322). Env: `DATABASE_URL=postgresql://postgres:postgres@db_storyhub:5432/postgres`.
- **Shares devcontainer with hummingbird** — same compose project, same containers. `glooctl up storyhub` is idempotent.
- Can run both hummingbird and storyhub dev servers simultaneously.
- **Override**: same `hb.yml` as hummingbird.

## Port Access from thinkpad

A combined SSH tunnel is configured on the thinkpad:

```bash
systemctl --user start gloo-tunnel
```

Forwards: `3000`, `3001`, `3006`, `8000` → bee.

| Port | Products | What |
|------|----------|------|
| 3000 | polymer (app) OR hummingbird (web) | **Conflict — don't run both** |
| 3001 | polymer (admin360) OR storyhub | **Conflict — don't run both** |
| 3006 | gpl | Next.js app |
| 8000 | hummingbird | API |

## Troubleshooting

```bash
glooctl status                                  # what's running
glooctl logs polymer -f                         # follow dev server logs
glooctl exec polymer -- pnpm install            # reinstall if node_modules is off
glooctl down polymer && glooctl up polymer      # full reset (loses container state, keeps host source)
```

If the devcontainer won't start:
```bash
podman ps -a --filter name=gloo-               # list all gloo containers
podman logs <container-name>                    # container-level logs
```

If port is already in use:
```bash
ss -tlnp sport = :3000                          # find what's using the port
# Likely another devcontainer publishing the same port — stop it first
glooctl down <conflicting-product>
```

If `pnpm install` fails with EACCES:
- The override file must include `userns_mode: "keep-id"` — this is required for rootless podman.
- Verify: `cat ~/.config/gloo/overrides/<product>.yml`

If env vars point to wrong services (e.g. `127.0.0.1:5433` instead of `polymer_db:5432`):
- Re-run setup: `glooctl setup <product>`
- Or manually edit the repo's `.env` / `.env.local` files on the host

## Nix Config

| File | Purpose |
|------|---------|
| `hosts/bee/gloo-dev.nix` | NixOS module: installs glooctl, podman, overrides, skill |
| `hosts/bee/gloo/glooctl` | CLI script |
| `hosts/bee/gloo/overrides/polymer.yml` | Polymer port publishing + UID fix |
| `hosts/bee/gloo/overrides/hb.yml` | Hummingbird/storyhub port publishing + UID fix |
| `hosts/bee/gloo/overrides/gpl.yml` | GPL UID fix |
| `hosts/bee/gloo/SKILL.md` | This skill |
| `hosts/bee/gloo/README.md` | Human-readable docs |
| `hosts/bee/configuration.nix` | Enables `services.gloo-dev` |

## Archive

Old module attempts (gloo.nix, gloo-containerized.nix, gloo-infra.nix) have been removed from the repo. Git history preserves them if ever needed.

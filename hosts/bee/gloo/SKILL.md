---
name: gloo-dev
description: Develop the Gloo stack using devcontainers on bee. Covers running containers, starting dev servers, and the full dev workflow. Load this skill when working on any Gloo project code or when interacting with the devcontainer infrastructure on bee.
---

# Gloo Dev Workflow on bee

You are working on **bee** (`10.10.0.12`). Gloo products run inside **devcontainers** — one per repo, using plain `podman compose`. No wrappers, no systemd units. All commands use `podman compose` directly.

## Architecture

```
bee (10.10.0.12)
└── Per-repo devcontainers (podman compose)
    ├── polymer      ~/Gloo/360-polymer      ports 3000, 3001
    ├── gpl          ~/Gloo/360-gpl          port 3006
    ├── hummingbird  ~/Gloo/360-hummingbird  ports 8000 (API), 3000 (web)
    └── storyhub     ~/Gloo/360-hummingbird  port 3001 (shares devcontainer with hummingbird)
```

Hummingbird and storyhub share the same devcontainer (same repo, same compose project `devcontainer`). They have separate dev commands and can run simultaneously.

## The Golden Rule

**ALL app commands run inside the devcontainer via `podman compose exec`.** Source files are bind-mounted (`../:/workspace`), so edits on the host are immediately reflected inside the container.

```bash
# CORRECT
podman compose exec app pnpm install
podman compose exec app pnpm dev

# WRONG — never do this on the host
pnpm install
npm run dev
```

## Override Files

Each product has a compose override file at `~/.config/gloo/overrides/`:

- `polymer.yml` — publishes 3000, 3001 + podman UID fix
- `hb.yml` — publishes 8000, 3000, 3001 + podman UID fix
- `gpl.yml` — podman UID fix (port 3006 already in devcontainer compose)

These are **podman-specific** (use `userns_mode: "keep-id"`) and must NOT be committed to product repos — they break Docker Desktop on macOS. Always use `-f` to layer them:

```bash
cd ~/Gloo/360-polymer/.devcontainer
podman compose -f docker-compose.yml -f ~/.config/gloo/overrides/polymer.yml up -d
```

## Typical Session

```bash
ssh -o IdentitiesOnly=yes crussell@10.10.0.12

# Start the devcontainer
cd ~/Gloo/360-hummingbird/.devcontainer
podman compose -f docker-compose.yml -f ~/.config/gloo/overrides/hb.yml up -d --build

# Run setup (first time or after clean)
podman compose exec dev bash -c "cd /workspace && bash .devcontainer/scripts/post-create-setup.sh"

# Start dev server (detached)
podman compose exec -d dev bash -c "cd /workspace && pnpm devcontainer:hb"

# Follow logs
podman compose logs -f dev

# Stop
podman compose down
```

For **polymer** and **gpl**, replace `dev` with `app` as the service name.

## Quick Reference

```bash
# ── Up ───────────────────────────────────────────────────────────
# polymer
cd ~/Gloo/360-polymer/.devcontainer
podman compose -f docker-compose.yml -f ~/.config/gloo/overrides/polymer.yml up -d --build

# gpl
cd ~/Gloo/360-gpl/.devcontainer
podman compose -f docker-compose.yml -f ~/.config/gloo/overrides/gpl.yml up -d --build

# hummingbird / storyhub (same devcontainer)
cd ~/Gloo/360-hummingbird/.devcontainer
podman compose -f docker-compose.yml -f ~/.config/gloo/overrides/hb.yml up -d --build

# ── Run commands ─────────────────────────────────────────────────
podman compose exec app pnpm install          # polymer, gpl
podman compose exec dev pnpm install          # hummingbird

# ── Dev server (detached) ───────────────────────────────────────
podman compose exec -d app pnpm dev                    # polymer or gpl
podman compose exec -d dev bash -c "cd /workspace && pnpm devcontainer:hb"
podman compose exec -d dev bash -c "cd /workspace && pnpm devcontainer:storyhub"

# ── Dev server (foreground / tmux) ─────────────────────────────
podman compose exec app pnpm dev                       # blocking
# or
tmux new -s polymer -d "podman compose exec app pnpm dev"

# ── Shell ────────────────────────────────────────────────────────
podman compose exec app bash                  # polymer, gpl
podman compose exec dev bash                  # hummingbird

# ── Stop ─────────────────────────────────────────────────────────
podman compose down
```

## Products & Ports

| Product | Repo | Compose service | Ports | Dev command |
|---------|------|----------------|-------|-------------|
| polymer | `~/Gloo/360-polymer` | `app` | 3000 (app), 3001 (admin360) | `pnpm dev` |
| gpl | `~/Gloo/360-gpl` | `app` | 3006 | `pnpm dev` |
| hummingbird | `~/Gloo/360-hummingbird` | `dev` | 8000 (API), 3000 (web) | `pnpm devcontainer:hb` |
| storyhub | `~/Gloo/360-hummingbird` | `dev` | 3001 | `pnpm devcontainer:storyhub` |

**Port conflicts:** polymer (3000) and hummingbird web (3000) can't run simultaneously. polymer admin360 (3001) and storyhub (3001) can't either.

## Environment Variables

Each repo uses `.env` / `.env.local` files (gitignored, backed by 1Password). They live inside the repo directory on the host and are bind-mounted into the devcontainer. They are **NOT** managed by Nix or agenix.

Each repo's `.devcontainer/scripts/setup-env.sh` creates env files from devcontainer templates on first run. Run it after `up`:

```bash
podman compose exec app bash .devcontainer/scripts/setup-env.sh    # polymer
podman compose exec dev bash -c "cd /workspace && bash .devcontainer/scripts/post-create-setup.sh"  # hummingbird
```

## Secrets

Each repo's `.env.local` values (API keys, auth secrets) are managed per-repo via 1Password. They are gitignored and NOT managed by Nix or agenix.

## Database Operations

Each devcontainer has its own postgres. Connection details are in the repo's env files.

**Polymer** (Drizzle):
```bash
podman compose exec app pnpm db:push
podman compose exec app pnpm db:seed
```

**Hummingbird API** (Prisma):
```bash
podman compose exec dev bash -c "cd /workspace && pnpm --filter api exec prisma generate"
podman compose exec dev bash -c "cd /workspace && pnpm --filter api exec prisma db push --force-reset --skip-generate"
```

**GPL** (Drizzle):
```bash
podman compose exec app pnpm run db:push
```

## Port Access from thinkpad

A combined SSH tunnel is configured on the thinkpad:

```bash
systemctl --user start gloo-tunnel
```

Forwards: `3000`, `3001`, `3006`, `8000` → bee.

| Port | Products | What |
|------|----------|------|
| 3000 | polymer (app) OR hummingbird (web) | **Conflict — mutually exclusive** |
| 3001 | polymer (admin360) OR storyhub | **Conflict — mutually exclusive** |
| 3006 | gpl | Next.js app |
| 8000 | hummingbird | API |

Alternatively, Caddy dev routes are available over Nebula at `*.dev.crussell.io`.

## Troubleshooting

```bash
# List all containers
podman ps -a

# Container-level logs
podman logs <container-name>

# Full reset (loses container state, keeps host source)
podman compose down
podman compose -f docker-compose.yml -f ~/.config/gloo/overrides/<product>.yml up -d --build

# Port already in use
ss -tlnp sport = :3000
# Likely another devcontainer — stop it first
```

If `pnpm install` fails with EACCES:
- The override file must include `userns_mode: "keep-id"` — required for rootless podman
- Verify: `cat ~/.config/gloo/overrides/<product>.yml`

## Nix Config

| File | Purpose |
|------|---------|
| `hosts/bee/gloo-dev.nix` | NixOS module: installs override files + skill |
| `hosts/bee/gloo/overrides/*.yml` | Port publishing + podman UID fix |
| `hosts/bee/gloo/SKILL.md` | This skill |
| `hosts/bee/configuration.nix` | Enables `services.gloo-dev` |

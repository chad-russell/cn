# Gloo Devcontainers on bee

Each Gloo product runs in its own devcontainer via `glooctl`. No shared host infra, no distrobox, no per-service Nix modules. The repo's `.devcontainer/` is the source of truth.

## Quick Start

```bash
ssh -o IdentitiesOnly=yes crussell@10.10.0.12

# Start a devcontainer + dev server
glooctl up polymer && glooctl start polymer
glooctl up hummingbird && glooctl start hummingbird
glooctl up storyhub && glooctl start storyhub    # shares devcontainer with hummingbird
```

## Access from thinkpad

```bash
# Start the tunnel (forwards all Gloo ports)
systemctl --user start gloo-tunnel

# Then browse on laptop:
#   http://localhost:3000  polymer app / hummingbird web
#   http://localhost:3001  admin360 / storyhub
#   http://localhost:3006  gpl
#   http://localhost:8000  hummingbird API
```

Polymer and hummingbird/storyhub both use port 3000 — don't run them simultaneously.

## glooctl Commands

```
glooctl up <product>                Build + start devcontainer, run setup
glooctl down <product>              Stop devcontainer (warns if sibling running)
glooctl down --force <product>      Stop devcontainer + sibling dev servers
glooctl setup <product>             Re-run postCreateCommand
glooctl shell <product>             Interactive shell
glooctl exec <product> -- <cmd>     Run one command
glooctl start <product> [-- <cmd>]  Start dev server (detached)
glooctl stop <product>              Stop dev server
glooctl restart <product>           Restart dev server
glooctl logs <product> [-f]         View dev server logs
glooctl status [product]            Show what's running
```

## Products & Ports

| Product | Repo | Ports | Dev command | Notes |
|---------|------|-------|-------------|-------|
| polymer | `~/Gloo/360-polymer` | 3000 (app), 3001 (admin360) | `pnpm dev` | Turborepo, Drizzle, WorkOS |
| gpl | `~/Gloo/360-gpl` | 3006 | `pnpm dev` | Next.js, Drizzle, needs hb-api for SSO |
| hummingbird | `~/Gloo/360-hummingbird` | 8000 (API), 3000 (web) | `pnpm devcontainer:hb` | Turborepo, Prisma |
| storyhub | `~/Gloo/360-hummingbird` | 3001 (app) | `pnpm devcontainer:storyhub` | Next.js, shares devcontainer with hummingbird |

**Hummingbird and storyhub share the same devcontainer** (same compose project `gloo-hb`). `glooctl up` is idempotent — running it for either product starts the shared containers. They have separate dev servers (separate systemd units).

## Environment Variables

`.env` / `.env.local` files live inside each repo, are gitignored, and are backed by 1Password. They are NOT managed by Nix or agenix. Each repo's `.devcontainer/scripts/setup-env.sh` creates the correct env files from devcontainer templates on first run.

## How It Works

- `glooctl up` runs `docker-compose up -d --build` with the repo's `.devcontainer/docker-compose.yml` plus a port publishing override from `~/.config/gloo/overrides/`.
- `glooctl start` runs the dev server as a systemd user unit via `docker-compose exec -T`. No blocking TUI — Turbo detects no TTY and outputs plain text.
- Logs go to `journalctl --user -u gloo-<product>`.
- Source is bind-mounted (`../:/workspace`), so host edits reflect instantly.
- Override files add `userns_mode: "keep-id"` to fix rootless podman UID mapping.

## Port Override Files

The repos' devcontainer compose files don't publish all app ports (they rely on VS Code's `forwardPorts`). `glooctl` adds override files:

- `polymer.yml` — publishes 3000, 3001 + UID fix
- `hb.yml` — publishes 8000, 3000, 3001 + UID fix
- `gpl.yml` — UID fix (port 3006 already published in devcontainer compose)

These live at `~/.config/gloo/overrides/` and are installed by Nix activation.

## Files

| File | Purpose |
|------|---------|
| `hosts/bee/gloo-dev.nix` | NixOS module |
| `hosts/bee/gloo/glooctl` | CLI script |
| `hosts/bee/gloo/overrides/*.yml` | Port overrides |
| `hosts/bee/gloo/SKILL.md` | Pi agent skill |
| `hosts/bee/gloo/README.md` | This file |

## Archive

Old module attempts have been removed. Git history preserves them if ever needed.

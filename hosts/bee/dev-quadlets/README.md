# bee remote dev stacks — podman user-quadlets (gpl, polymer, buildspace, hummingbird, storyhub, openbible)

This mirrors the **thinkpad's** rootless user-quadlet dev setup onto `bee`, so
you can use bee as a remote dev machine for the Gloo/buildspace/Wycliffe
projects. Same container images, same `dev-server.sh` model, same on-demand (no
auto-start) behavior — delivered **NixOS-declaratively** and reached over **SSH
port-forward tunnels** so the apps see `localhost` exactly as they do on the
thinkpad.

> **Why tunnels, not a reverse proxy.** Next.js dev servers hard-code localhost
> assumptions: the HMR/dev channel is restricted to localhost origins (Next.js
> `allowedDevOrigins`), and gpl/polymer auth clients fall back to `localhost:3000`
> / `3006`. Fronting them with a non-localhost proxy (Caddy) breaks hydration and
> auth and would require editing the product repos (incl. personal hostnames — a
> no-go for the team repos). SSH-forwarding `localhost` sidesteps all of it: zero
> product-repo changes, every callback/cookie/HMR URL works unchanged.

## Architecture

```
~/Gloo/360-gpl, ~/Gloo/360-polymer, ~/Gloo/360-hummingbird, ~/Gloo/open-bible, ~/buildspace
                                              cloned product repos on bee
~/.../hosts/bee/dev-quadlets/{gpl,polymer,buildspace,hummingbird,storyhub,openbible}/
├── *.network / *.volume / *.container              quadlet input files
├── *.build / *.Containerfile                        storyhub custom image build
├── dev-server.sh                                   PID 1 of each app container
hosts/bee/dev-quadlets.nix                          NixOS module that wires it all up
hosts/thinkpad/Justfile (cjust dev-tunnel / dev-up) laptop-side SSH tunnel recipes
```

The NixOS module (`hosts/bee/dev-quadlets.nix`):

1. Materializes the quadlet units + `dev-server.sh` read-only under
   `/etc/dev-quadlets/<project>/` (Nix store symlinks).
2. Symlinks the `*.container` / `*.volume` / `*.network` files into
   `~/.config/containers/systemd/` (the rootless user-quadlet search path) for
   `crussell`, then `systemctl --user daemon-reload`s.
3. Ships a `qd` wrapper on bee (one script for all projects).

So `nix run .#deploy -- bee` registers/updates everything — **no manual install
step, no `cn` checkout required on bee.** Linger is on for `crussell`, so the
user manager (and the user podman socket) is always up.

## What runs (per project)

| Project | App image | DB | S3 | Tunnel ports (laptop `localhost:`) |
| --- | --- | --- | --- | --- |
| gpl | `devcontainers/javascript-node:22` | postgres:15 | minio | `3006` |
| polymer | `devcontainers/javascript-node:24` | postgres:16 | minio | `3000` (polymer), `3001` (admin360) |
| buildspace | `oven/bun:1.3.14` | postgres:17 | minio (pinned) | `3000`, `3002`, `3003`, `3004`, `3005`, `3006`, `3008`, `3010` |
| hummingbird | `devcontainers/javascript-node:24` | postgres:16 | — | `3000` (web), `8000` (api) |
| storyhub | `localhost/storyhub-dev:latest` (custom build) | postgres:16 | minio | `3001` (web), `8001` (worker), `9000` (minio API), `9001` (minio console) |
| openbible | `devcontainers/javascript-node:22` | postgres:17 | minio | `3000` (web), `9876` (api), `9000` (minio API), `9001` (minio console) |

All app containers run as **root (UID 0) inside the container** — in
rootless podman that maps to crussell on the host, so bind-mount artifacts
(`node_modules`, `.next`, caches) land crussell-owned. The thinkpad units use
`UserNS=keep-id` for this, but bee's rootless podman + native overlay breaks
keep-id (recursive-userns permission error), so bee runs `User=0` instead — same
ownership outcome.

### Hummingbird-specific notes

- **No MinIO.** The Hummingbird API's `aws.ts` controller requires S3/CloudFront
  env vars at module load (throws on boot without them), but the stack boots fine
  with dummy values matching `.devcontainer/envs/api.env.devcontainer`. File
  upload/viewing won't work, but all project management features do.
- **Two dev servers in one container** (like polymer): Express API on `:8000` +
  Vite web on `:3000`, launched by `dev-server.sh`.
- **Prisma + Rev79 codegen** run at every start (the API imports both at boot).

### StoryHub-specific notes

- **Custom image build** (`storyhub-dev.build` → `localhost/storyhub-dev:latest`).
  The worker needs heavy system deps (vips, libreoffice, imagemagick, ghostscript,
  ffmpeg, pandoc, markitdown) that no published image has. The `.build` quadlet
  unit builds from `storyhub-dev.Containerfile` on first start; layer caching
  makes subsequent builds fast. First build takes ~15-20 minutes (libreoffice +
  texlive are large).
- **Two dev servers in one container:** StoryHub web (Next.js `:3001`) + worker
  (Bun/Hono `:8001`).
- **Dual S3 endpoints:** the web app uses `S3_ENDPOINT=http://localhost:9000`
  (presigned URLs the browser must reach), while the worker overrides it inline
  to `http://storyhub-minio:9000` (server-side file downloads). See
  `storyhub/dev-server.sh` for details.
- **MinIO ports published to host** (`3390`/`3391`) and included in the SSH
  tunnel, because presigned upload URLs embed the S3_ENDPOINT host — the browser
  needs to reach MinIO at `localhost:9000`.
- **STORYHUB_STANDALONE=true** by default — StoryHub runs without requiring the
  Hummingbird API for auth (uses dev session data). To use real HB auth
  integration, set `HUMMINGBIRD_API_URL` to the Hummingbird container hostname
  and start the hummingbird stack too.

### Open.Bible-specific notes

- **Repo:** `~/Gloo/open-bible` (biblica/open-bible — pnpm + Turborepo monorepo).
  Next.js 15 + Payload CMS 3 web (`apps/web`), Hono/Drizzle API (`apps/api`).
  NOTE: distinct from `~/Gloo/360-open-bible` (TangoGroup's older Next.js-only
  build of the same site) and `360-open-bible-api` (the API-only extraction).
- **Two dev servers in one container** (like hummingbird/storyhub): Payload web
  `next dev` on `:3000` + Hono API `tsx watch` on `:9876` (repo compose
  convention; `OPEN_BIBLE_API_BASE_URL=http://localhost:9876` points web at it).
- **ONE Postgres, TWO schemas** (mirrors prod's shared Aurora): Payload tables
  in `public` (`DATABASE_URI`), Drizzle API tables in `api` (`DATABASE_URL`).
  Both migrators run on every start (`payload:migrate` + the api's library
  migrator); a stale `dev` row in `payload_migrations` is deleted first to
  avoid the non-TTY "data loss? (y/N)" hang.
- **S3_ENDPOINT=localhost:9000 + in-container forwarder.** Payload's s3Storage
  plugin uses `clientUploads` — the browser must reach MinIO at the same URL
  the server uses. dev-server.sh runs a tiny TCP forwarder
  `localhost:9000 -> openbible-minio:9000` inside the app container, so one
  URL serves both (browser via SSH tunnel → bee:3402, server via forwarder).
  Two buckets auto-created: `open-bible-v2-media-items` (web media) +
  `open-bible-artifacts` (api).
- **ETL not run** (`apps/etl`): it polls the DBL API and needs DBL credentials;
  in the repo it's a GitHub-Actions-triggered ECS task, not a dev companion.
- **Seeding:** content pages seed via `pnpm --filter @open-bible/web seed`
  (idempotent find-or-create) automatically after the web server answers;
  Payload dev admin auto-login gives you an admin session without credentials
  in dev (`DISABLE_ADMIN_AUTO_LOGIN=true` env to test login screens).
- **Linear tickets are BIB-###** in this repo family (BIB prefix spans the
  qrcode.bible + open-bible projects).

## Daily use

**1. Start the stack on bee** (db + minio + app, on-demand — nothing auto-starts):

```bash
ssh -o IdentitiesOnly=yes crussell@10.10.0.12
qd gpl up              # or: systemctl --user start gpl-dev-app
qd gpl status          # status of app + db + minio
qd gpl logs            # journalctl --user -u gpl-dev-app -f
qd gpl down            # stops app + db + minio (PartOf= cascade)
# same for:  qd polymer ...   |   qd buildspace ...
#            qd hummingbird ... (or: qd hb ...)
#            qd storyhub ...   (or: qd sh ...)
#            qd openbible ...
```

**2. Open the tunnel from your laptop** and browse `localhost`:

```bash
cjust dev-up gpl          # start gpl on bee AND open the tunnel (one shot)
# — or, if the stack is already running on bee —
cjust dev-tunnel gpl          # then browse http://localhost:3006
cjust dev-tunnel polymer      # http://localhost:3000 + http://localhost:3001
cjust dev-tunnel buildspace   # 8 ports: 3000,3002–3006,3008,3010
cjust dev-tunnel hummingbird  # http://localhost:3000 (web) + http://localhost:8000 (api)
cjust dev-tunnel storyhub     # http://localhost:3001 (web) + :8001 + :9000 + :9001
cjust dev-tunnel openbible    # http://localhost:3000 (web) + :9876 (api) + :9000/:9001 (minio)
```

Ctrl-C closes a tunnel. `cjust dev-tunnel <project>` forwards the **same** ports
you'd use on the thinkpad onto bee's offset published ports; the apps can't tell
the difference from local dev.

### Port scheme

bee also runs the former buzz-relay (which used to own bee's `:3000` and `:5000`; removed 2026-08-20), so
the dev stacks publish on **offset host ports** on bee that never collide with
each other (the buzz-relay is gone): gpl `:3006`, polymer `:3100`/`:3101`, buildspace
`:32xx`, hummingbird `:3300`/`:3308`, storyhub `:3301`/`:3309`/`:3390`/`:3391`,
openbible `:3400`/`:3401`/`:3402`/`:3403`.
The `cjust dev-tunnel` (and `cjust dev-up`) re-maps those onto the
thinkpad-standard localhost ports (`:3000`, `:3006`, …) so nothing in the apps or
your muscle memory changes. Because the projects use disjoint host-port
ranges on bee, they all *can* run simultaneously — see the RAM caveat below.

> **RAM is the real limiter, not ports.** The dev compilers are memory-heavy
> (polymer's Turbopack app alone peaks ~20 GB; buildspace's turbo runs 8+ apps;
> bee has 27 GB + zram swap). Running polymer + buildspace at once can OOM-kill a
> dev server (native segfault). For stability, run **one heavy project at a time**
> (gpl is light; polymer and buildspace are heavy; hummingbird is medium;
> storyhub is light-medium). `qd <project> restart` brings a crashed stack back.

### Laptop port collisions

On the laptop, several projects share `localhost:3000`: polymer, buildspace, and
hummingbird. Run one at a time (same rule as local dev on the thinkpad).

## First run (per project)

> **One-time: clear host-installed `node_modules`.** Each repo was previously run
> on bee's **host** (pnpm/bun via Nix), so its `node_modules/` is incompatible
> with the container's toolchain — `pnpm exec`/turbo will fail with a
> `confirmModulesPurge`/reconcile prompt or native errors. Before the first
> `qd <project> up`, delete it once so `dev-server.sh` does a fresh in-container
> install:
> ```bash
> rm -rf ~/Gloo/360-gpl/node_modules      # or 360-polymer, 360-hummingbird, or ~/buildspace
> ```

The first `start` installs deps inside the container against the live bind mount
and boots against a **fresh, empty** postgres. Once the app container is up, push
the schema:

```bash
# gpl
podman exec gpl-quadlet-app pnpm db:push
podman exec gpl-quadlet-app pnpm db:seed   # optional; creates admin@gpl.org/admin123

# polymer — db:seed is REQUIRED (not optional): it creates the Gloo system org
# (external_org_id matching the WorkOS staging org) + your user record + org
# membership. Without it, WorkOS login succeeds but the dashboard throws
# "Organization not found" on first load.
podman exec polymer-quadlet-app pnpm db:push
podman exec polymer-quadlet-app pnpm db:seed

# buildspace
podman exec buildspace-quadlet-app bun db:migrate
podman exec buildspace-quadlet-app bun db:seed   # optional; creates the super_admin below

# hummingbird — restores from .devcontainer/hummingbird_dev_dump.sql (realistic
# project data: templates, plans, progress, book/goal data), then overlays dev
# users (admin, collaborator, sfc, fc, etc.) for simplified local login.
# Login with: admin, sfc, fc, collaborator, vision, uploader, sfc2, reporter, regional
# Password is the same for all dev users.
podman exec hummingbird-quadlet-app bash -lc 'cd /workspace && CONN_URL=postgresql://postgres:postgres@hummingbird-db:5432/postgres pnpm --filter api run seed'

# storyhub — runs prisma:generate + prisma:push + seed. Creates a default
# workspace + admin HummingbirdUser record. Destructive (wipes existing data).
podman exec storyhub-quadlet-app bash -lc 'cd /workspace && pnpm --filter storyhub-prisma run seed'

# openbible — migrations + seed run automatically on every start (see the
# Open.Bible notes above); nothing extra needed. Re-seed manually if desired:
podman exec openbible-quadlet-app pnpm --filter @open-bible/web seed
```

(MinIO buckets are created automatically by each `dev-server.sh`.)

## Editing the units / scripts

Edit a file under `hosts/bee/dev-quadlets/<project>/`, then redeploy bee:

```bash
# from the deploy origin (bees)
nix run .#deploy -- bee
```

The activation script re-symlinks the units and daemon-reloads crussell's user
manager. Start/restart the stack to pick up container-level changes:

```bash
qd gpl restart
```

For storyhub, editing the `Containerfile` requires a rebuild — the `.build`
quadlet unit handles this automatically on restart, but you can force a clean
rebuild:

```bash
podman image rm localhost/storyhub-dev:latest
qd sh restart
```

## How it behaves (by design)

- **No auto-start on boot.** No unit has an `[Install]` section → nothing is
  enabled; stacks run only when you `start` them.
- **Dev server is PID 1, no auto-restart.** If a dev server crashes, the
  container stops so you can read the logs and `restart` it — no restart loop.
- **DB + MinIO data persist** in the `systemd-<project>-dev-db` /
  `systemd-<project>-dev-minio` volumes across stop/start.
- **Coexists with the former buzz-relay quadlets** on bee (removed 2026-08-20; the port-offset scheme remains) — completely
  separate podman stores (root vs crussell).

## Differences from the thinkpad setup

- **Delivered by a NixOS module** (`hosts/bee/dev-quadlets.nix`) instead of
  per-project `install.sh` symlinks — no `cn` checkout needed on bee.
- **No SELinux** → the `:Z`/`:z` Volume suffixes from the thinkpad units are
  dropped.
- **Repo paths** use `/home/crussell` (not `/var/home/crussell`); buildspace
  lives at `~/buildspace` (not `~/Code/buildspace`).
- **`dev-server.sh` is Nix-managed** (bind-mounted from
  `/etc/dev-quadlets/<project>/`); otherwise identical to the thinkpad — no
  proxy/auth overrides, because the SSH tunnel makes the app see `localhost`.
- **App containers run as `User=0`** (not `UserNS=keep-id`) — bee's rootless
  overlay breaks keep-id; `User=0` gives the same crussell-owned bind mounts.

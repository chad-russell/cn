# GPL dev stack — podman quadlet (parallel to the compose setup)

A **standalone podman-quadlet** version of the gpl dev environment, running
side-by-side with the repo's own `docker-compose.yml` / `.devcontainer` compose
files. The compose files are **not touched at all**; this lives entirely under
`~/Code/cn/gloo/quadlets/gpl/` and uses its own container / network / volume /
image names so the two never collide.

> Path note: you may see this as `/work/Code/cn/gloo/quadlets/gpl/`; on the host
> the real tree is under the home dir, i.e. `~/Code/cn/gloo/quadlets/gpl/`
> (Silverblue → `/var/home/crussell/...`). The unit files use the real path.

## What it runs

| Unit file                | Becomes systemd service        | Podman resource                       |
| ------------------------ | ------------------------------ | ------------------------------------- |
| `gpl-dev.network`        | `gpl-dev-network.service`      | network `systemd-gpl-dev`             |
| `gpl-dev-db.volume`      | `gpl-dev-db-volume.service`    | volume `systemd-gpl-dev-db`           |
| `gpl-dev-minio.volume`   | `gpl-dev-minio-volume.service` | volume `systemd-gpl-dev-minio`        |
| `gpl-dev-db.container`   | `gpl-dev-db.service`           | container `gpl-quadlet-db` (alias `gpl-db`)      |
| `gpl-dev-minio.container`| `gpl-dev-minio.service`        | container `gpl-quadlet-minio` (alias `gpl-minio`) |
| `gpl-dev-app.container`  | `gpl-dev-app.service`          | container `gpl-quadlet-app` (publishes **3006**) |

The app runs from the **published** `mcr.microsoft.com/devcontainers/javascript-node:22`
image (node 22 + corepnpm) — the same image the repo's devcontainer uses. Unlike
the polymer quadlet there is **no `.build` unit**, because gpl has no custom
Dockerfile; podman pulls the image on first start. Nothing is vendored into the
gpl repo: only the repo itself is bind-mounted (live code), and `dev-server.sh`
lives outside the repo.

## Differences from the polymer quadlet

- **No `.build` unit** — gpl's devcontainer image is published, not built from a
  repo Dockerfile.
- **S3 is fully wired up.** The repo's compose creates a `gpl-assets` bucket via
  a `minio-init` service; here, `dev-server.sh` creates it on app start using the
  repo's own `@aws-sdk/client-s3` dependency (no separate `minio/mc` container).
- **No `.env.local` required to boot.** better-auth has a dev fallback secret and
  we inject `DATABASE_URL` / `S3_*` directly, so the stack starts with zero repo
  files. Add `.env.local` only if you need integration secrets (Hummingbird,
  Salesforce, Google) — Next.js loads it from the bind mount automatically.
- **Postgres readiness via node**, not `pg_isready` (the base image lacks it).

## Install (once, and after any edit to a unit file)

```bash
~/Code/cn/gloo/quadlets/gpl/install.sh
```

This symlinks the unit files into `~/.config/containers/systemd/` and runs
`systemctl --user daemon-reload`.

## Daily use

```bash
# Start the whole stack (pulls the image + installs deps the first time):
systemctl --user start gpl-dev-app

# Stop the whole stack (db + minio stop too, via PartOf=):
systemctl --user stop gpl-dev-app

# Restart just the app:
systemctl --user restart gpl-dev-app

# Status / logs:
systemctl --user status gpl-dev-app
journalctl --user -u gpl-dev-app -f
```

There's also a tiny optional wrapper `qd` (sister to the polymer `qd`):

```bash
~/Code/cn/gloo/quadlets/gpl/qd gpl up
~/Code/cn/gloo/quadlets/gpl/qd gpl down
~/Code/cn/gloo/quadlets/gpl/qd gpl status   # status of app + db + minio
~/Code/cn/gloo/quadlets/gpl/qd gpl logs
```

Then browse to **http://localhost:3006** (gpl).

## How it behaves (by design)

- **No auto-start on boot.** No unit has an `[Install]` section, so nothing is
  enabled — the stack only runs when you `systemctl --user start` it.
- **Only 3006 is published** to the host. Postgres and MinIO (API + console) are
  reachable on the internal network only (no `5432` / `9000` / `9001`). Want the
  MinIO console in your browser? Add `PublishPort=9001:9001` to
  `gpl-dev-minio.container`, re-run `install.sh`, and restart.
- **Dev server is PID 1, no auto-restart.** If the Next.js server crashes, the
  container stops so you can read the logs and `restart` it — no restart loop.
- **DB and MinIO data persist** in the `systemd-gpl-dev-db` /
  `systemd-gpl-dev-minio` volumes across stop/start.

## First run: push DB schema

The first `start` runs `pnpm install` inside the container (see `dev-server.sh`)
and starts the dev server against a **fresh, empty** postgres. Push the schema
once the app container is up:

```bash
podman exec gpl-quadlet-app pnpm db:push
podman exec gpl-quadlet-app pnpm db:seed   # optional
```

(The MinIO `gpl-assets` bucket is created automatically by `dev-server.sh` — no
manual step needed.)

## Updating the toolchain image

Only needed when you want a newer `javascript-node:22` (code changes are picked
up live via the bind mount — no rebuild). gpl has no local build, so just re-pull:

```bash
podman image pull mcr.microsoft.com/devcontainers/javascript-node:22
systemctl --user restart gpl-dev-app
```

## Editing the units

Edit a file here, then:

```bash
~/Code/cn/gloo/quadlets/gpl/install.sh   # re-symlinks + daemon-reload
systemctl --user restart gpl-dev-app
```

You can preview the exact generated service with:

```bash
/usr/lib/systemd/system-generators/podman-system-generator --user --dryrun | sed -n '/gpl-dev-app.service/,/^$/p'
```

## Coexistence with the compose stack / polymer quadlet

- **gpl compose:** the two use completely separate names, but they **cannot run
  at the same time** because both publish host port 3006. Pick one — either the
  repo's own `docker compose up` or this quadlet stack.
- **polymer quadlet:** safe to run simultaneously — polymer publishes 3000/3001,
  gpl publishes 3006, no collision.

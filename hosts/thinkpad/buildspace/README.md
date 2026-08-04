# Buildspace dev stack — podman quadlet

A **standalone podman-quadlet** version of the buildspace dev environment, the
sibling of the gloo quadlets under `hosts/thinkpad/gloo/`. It runs the whole
Bun/Turborepo monorepo locally on the thinkpad in one app container, plus
Postgres and MinIO sidecars. The repo's own `docker-compose.local.yml` is **not
touched at all**; this lives entirely under
`~/Code/cn/hosts/thinkpad/buildspace/` and uses its own container / network /
volume / image names so the two never collide.

## Architecture

```
~/Code/buildspace/                          cloned repo (code, live-mounted)
~/Code/cn/hosts/thinkpad/buildspace/        THIS — orchestration (tracked)
├── *.network / *.volume / *.container      quadlet units
├── dev-server.sh                           PID 1 of the app container
├── install.sh                              symlinks units + daemon-reload
├── qd                                      convenience systemctl wrapper
└── README.md
```

## What it runs

| Unit file                       | Becomes systemd service               | Podman resource                                   |
| ------------------------------- | ------------------------------------- | ------------------------------------------------- |
| `buildspace-dev.network`        | `buildspace-dev-network.service`      | network `systemd-buildspace-dev`                  |
| `buildspace-dev-db.volume`      | `buildspace-dev-db-volume.service`    | volume `systemd-buildspace-dev-db`                |
| `buildspace-dev-minio.volume`   | `buildspace-dev-minio-volume.service` | volume `systemd-buildspace-dev-minio`             |
| `buildspace-dev-db.container`   | `buildspace-dev-db.service`           | container `buildspace-quadlet-db` (alias `postgres`)   |
| `buildspace-dev-minio.container`| `buildspace-dev-minio.service`        | container `buildspace-quadlet-minio` (alias `minio`)  |
| `buildspace-dev-app.container`  | `buildspace-dev-app.service`          | container `buildspace-quadlet-app` (publishes 8 ports) |

The app runs from the **published** `oven/bun:1.3.14` image — the same base the
repo's `containers/dev/Dockerfile` starts from and the version `packageManager`
pins. There is **no `.build` unit**: podman pulls the image on first start and
`bun install` runs against the live bind mount. The dev server fan-out is
`bun dev` → `turbo run dev`, which starts every workspace's `dev` script in
parallel (concurrency 20). Nothing is vendored into the buildspace repo: only the
repo itself is bind-mounted (live code), and `dev-server.sh` lives outside the
repo.

### Ports (published to host)

| Port  | App          | Port  | App          |
| ----- | ------------ | ----- | ------------ |
| 3000  | marketplace  | 3005  | studio       |
| 3002  | runtime      | 3006  | super-admin  |
| 3003  | login        | 3008  | registry     |
| 3004  | docs         | 3010  | jobs         |

`code-review` (3007) is **not** published — it is reached by `jobs` over the
shared container loopback at `http://localhost:3007` (`CODE_REVIEW_SVC_URL`),
mirroring how `docker-compose.local.yml` keeps it internal. Postgres and MinIO
(API + console) are also internal-only.

## Differences from the gloo quadlets

- **Bun, not pnpm/node.** Image is `oven/bun:1.3.14`; `bun install` at first
  start; dev surface is `bun dev` (turbo) rather than a hand-launched Next.js.
- **No `UserNS=keep-id`.** The gloo units use `keep-id` because the devcontainers
  image runs as the `node` user (UID 1000). The `oven/bun` image runs as root,
  and rootless podman maps container UID 0 → your host user automatically, so
  bind-mount writes (`node_modules`, `.next` caches) come out owned by you
  without any userns flag. (`:Z` on the repo volume handles SELinux labeling,
  since `~/Code/buildspace` isn't pre-labeled the way `~/Gloo` is.)
- **Many apps from one container.** Rather than one `.container` per app (as the
  gloo projects' single-app model implies), this runs all 10 workspaces through
  turbo inside one container — the "single app container" choice, applied to a
  monorepo.
- **Turbo `--env-mode=loose`.** `turbo.json` declares `env` on the `build` task,
  which engages turbo's STRICT env mode and would strip `DATABASE_URL` (and the
  rest) from each dev task — `packages/db`'s `drizzle-kit studio` and
  `apps/runtime` both crash on a missing env at boot. So `dev-server.sh` invokes
  `turbo run dev --env-mode=loose` directly (not the repo's bare `bun dev`) to
  forward the container's full environment to every task. No repo change.
- **Two extra env vars beyond compose**, required for a zero-config local boot:
  `RESEND_API_KEY=re_local_dev_placeholder` (apps/runtime constructs
  `new Resend(...)` unconditionally at boot and throws on a falsy key) and
  `BUILDSPACE_SUPER_ADMIN_EMAILS=test@buildspace.so` (the super-admin + studio
  allowlist; matches the seeded super_admin created by `bun db:seed`). Stripe /
  GitHub / git-hosting are conditional and stay null/healthy without their keys.
- **MinIO bucket is auto-created** on app start by `dev-server.sh` (best-effort),
  using the repo's own `@aws-sdk/client-s3`. The repo's `bun storage:init`
  script does **not** work here (it shells out to the compose `minio-setup`
  service), so the bucket init is done inline instead.

## Install (once, and after any edit to a unit file)

```bash
~/Code/cn/hosts/thinkpad/buildspace/install.sh
```

This symlinks the unit files into `~/.config/containers/systemd/` and runs
`systemctl --user daemon-reload`.

## Daily use

```bash
# Start the whole stack (pulls image + bun install on the first run):
systemctl --user start buildspace-dev-app

# Stop the whole stack (db + minio stop too, via PartOf=):
systemctl --user stop buildspace-dev-app

# Restart just the app:
systemctl --user restart buildspace-dev-app

# Status / logs:
systemctl --user status buildspace-dev-app
journalctl --user -u buildspace-dev-app -f
```

There's also a tiny optional wrapper `qd`:

```bash
~/Code/cn/hosts/thinkpad/buildspace/qd buildspace up
~/Code/cn/hosts/thinkpad/buildspace/qd buildspace down
~/Code/cn/hosts/thinkpad/buildspace/qd buildspace status   # status of app + db + minio
~/Code/cn/hosts/thinkpad/buildspace/qd buildspace logs
```

Then browse to **http://localhost:3000** (marketplace) and the other ports above.

## How it behaves (by design)

- **No auto-start on boot.** No unit has an `[Install]` section, so nothing is
  enabled — the stack only runs when you `systemctl --user start` it. (Even if
  you `enable`d it, user units only start at login unless lingering is on, which
  it isn't here.)
- **Only the 8 app ports are published** to the host. Postgres, MinIO, and
  code-review are reachable on the internal network / loopback only. Want the
  MinIO console in your browser? Add `PublishPort=9001:9001` to
  `buildspace-dev-minio.container`, re-run `install.sh`, and restart. Want a DB
  GUI? Add `PublishPort=5434:5432` to `buildspace-dev-db.container`.
- **Dev server is PID 1, no auto-restart.** If turbo (or an app under it)
  crashes, the container stops so you can read the logs and `restart` it — no
  restart loop.
- **DB and MinIO data persist** in the `systemd-buildspace-dev-db` /
  `systemd-buildspace-dev-minio` volumes across stop/start.

## First run: push DB schema

The first `start` runs `bun install` inside the container (see `dev-server.sh`)
and starts the dev servers against a **fresh, empty** postgres. Push the schema
once the app container is up:

```bash
podman exec buildspace-quadlet-app bun db:migrate
podman exec buildspace-quadlet-app bun db:seed   # optional; creates the super_admin below
```

After seeding, sign in at **http://localhost:3003/sign-in** as:

```
test@buildspace.so  /  password123
```

This account is allowlisted for super-admin (`BUILDSPACE_SUPER_ADMIN_EMAILS` is
preset to `test@buildspace.so`).

(The MinIO `buildspace-internal` bucket is created automatically by
`dev-server.sh` — no manual step needed.)

## Updating the toolchain image

Only needed when you want a newer `bun` (code changes are picked up live via the
bind mount — no rebuild). The repo pins `bun@1.3.14` (`packageManager` +
`containers/dev/Dockerfile`); bump the tag here to match when you upgrade:

```bash
podman image pull docker.io/oven/bun:1.3.14
systemctl --user restart buildspace-dev-app
```

## Editing the units

Edit a file here, then:

```bash
~/Code/cn/hosts/thinkpad/buildspace/install.sh   # re-symlinks + daemon-reload
systemctl --user restart buildspace-dev-app
```

You can preview the exact generated service with:

```bash
/usr/lib/systemd/system-generators/podman-system-generator --user --dryrun | sed -n '/buildspace-dev-app.service/,/^$/p'
```

## A note on Next.js host binding

`bun dev` runs each app's repo-defined `dev` script as-is. The Hono apps
(runtime, jobs, code-review) use `Bun.serve`, which binds to `0.0.0.0` by
default, so their published ports are reachable immediately. The Next.js apps
use `next dev [--port N]`; Next.js binds to `0.0.0.0` by default, so those ports
are reachable too. If a Next.js port ever turns out unreachable from the host
(a Next version changing its default bind), add `--hostname 0.0.0.0` to that
app's `dev` script in the repo, or switch `dev-server.sh` to launch the apps
explicitly (the way `docker-compose.local.yml` does).

## Known issues (upstream, not the quadlet)

- **Studio (`:3005`) returns HTTP 500** under Next.js 16 + Turbopack:
  `Cannot find package 'pg-<hash>'` in an SSR chunk. This reproduces with the
  repo's own `next dev` (Turbopack) and is a build-tool module-resolution bug,
  not a container/env problem. The other 7 published apps serve 200. If you need
  studio locally, run it without Turbopack (`next dev --no-turbo` in
  `apps/studio`) — a repo-level change.
- **`code-review` (`:3007`)** is intentionally not published; `jobs` reaches it
  over the shared container loopback. GET `http://localhost:3010/` on the jobs
  worker returns 404 (no root route) — the server is healthy; check the app logs
  for real readiness.

## Coexistence with the compose stack

The two stacks use completely separate names, so they never collide — but they
**cannot run at the same time** because both publish host ports 3000/3002–3006/
3008/3010. Pick one:

```bash
# compose (repo):
cd ~/Code/buildspace && bun dev:up     # ...then bun dev:down before using the quadlet

# quadlet (this):
systemctl --user start buildspace-dev-app
```

Safe to run alongside the gloo quadlets (polymer: 3000/3001, gpl: 3006) — but
note buildspace's marketplace (3000) collides with polymer, and buildspace's
super-admin (3006) collides with gpl. Don't run those pairs simultaneously.

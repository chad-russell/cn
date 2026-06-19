# Polymer dev stack — podman quadlet (parallel to the compose setup)

A **standalone podman-quadlet** version of the polymer dev environment, running
side-by-side with the existing `podman compose` setup under
`~/Gloo/360-polymer/.devcontainer`. The existing compose files are **not touched
at all**; this lives entirely under `~/Code/cn/gloo/quadlets/polymer/` and uses
its own container / network / volume / image names so the two never collide.

> Path note: you referred to this as `/work/Code/cn/gloo/quadlets/polymer/`;
> the real tree is under the home dir, so it's `~/Code/cn/gloo/quadlets/polymer/`
> (no `/work` mount exists). Move it if you meant a different root.

## What it runs

| Unit file                     | Becomes systemd service             | Podman resource                      |
| ----------------------------- | ----------------------------------- | ------------------------------------ |
| `polymer-dev.network`         | `polymer-dev-network.service`       | network `systemd-polymer-dev`        |
| `polymer-dev-db.volume`       | `polymer-dev-db-volume.service`     | volume `systemd-polymer-dev-db`      |
| `polymer-dev-minio.volume`    | `polymer-dev-minio-volume.service`  | volume `systemd-polymer-dev-minio`   |
| `polymer-dev-db.container`    | `polymer-dev-db.service`            | container `polymer-quadlet-db` (alias `polymer_db`)   |
| `polymer-dev-minio.container` | `polymer-dev-minio.service`         | container `polymer-quadlet-minio` (alias `polymer_minio`) |
| `polymer-dev-app.container`   | `polymer-dev-app.service`           | container `polymer-quadlet-app` (publishes **3000 + 3001**) |

The app runs from the **published** `mcr.microsoft.com/devcontainers/javascript-node:24`
image (node 24, pnpm via corepack) — the same `node:24-bookworm` base the repo's
own `.devcontainer/Dockerfile` starts from, so behavior is equivalent. There is
**no `.build` unit**: podman pulls the image on first start. Nothing is vendored
into the polymer repo — only the repo itself is bind-mounted (live code), and
`dev-server.sh` lives outside the repo. The app reaches postgres/minio via the
`polymer_db` / `polymer_minio` network aliases, which match what `.env.local`
already expects.

## Install (once, and after any edit to a unit file)

```bash
~/Code/cn/gloo/quadlets/polymer/install.sh
```

This symlinks the unit files into `~/.config/containers/systemd/` and runs
`systemctl --user daemon-reload`.

## Daily use

```bash
# Start the whole stack (pulls the image + installs deps the first time):
systemctl --user start polymer-dev-app

# Stop the whole stack (db + minio stop too, via PartOf=):
systemctl --user stop polymer-dev-app

# Restart just the app:
systemctl --user restart polymer-dev-app

# Status / logs:
systemctl --user status polymer-dev-app
journalctl --user -u polymer-dev-app -f
```

There's also a tiny optional wrapper `qd` (sister to the `dev` script):

```bash
~/Code/cn/gloo/quadlets/polymer/qd polymer up
~/Code/cn/gloo/quadlets/polymer/qd polymer down
~/Code/cn/gloo/quadlets/polymer/qd polymer status   # status of app + db + minio
~/Code/cn/gloo/quadlets/polymer/qd polymer logs
```

Then browse to **http://localhost:3000** (polymer) and **http://localhost:3001** (admin360).

## How it behaves (by design)

- **No auto-start on boot.** No unit has an `[Install]` section, so nothing is
  enabled — the stack only runs when you `systemctl --user start` it. (Even if
  you `enable`d it, user units only start at login unless lingering is on, which
  it isn't here.)
- **Only 3000 and 3001 are published** to the host. Postgres and MinIO are
  reachable on the internal network only (no `54324` / `9004` / `9005`).
- **Postgres readiness via node**, not `pg_isready` (the base image lacks it).
- **Dev server is PID 1, no auto-restart.** If a Next.js server crashes, the
  container stops so you can read the logs and `restart` it — no restart loop.
- **DB data persists** in the `systemd-polymer-dev-db` volume across stop/start.

## First run: install deps + push DB schema

The first `start` runs `pnpm install` inside the container (see `dev-server.sh`)
and starts the dev servers against a **fresh, empty** postgres. Push the schema
once the app container is up:

```bash
podman exec polymer-quadlet-app pnpm db:push
podman exec polymer-quadlet-app pnpm db:seed   # optional
```

## Updating the toolchain image

Only needed when you want a newer `javascript-node:24` (code changes are picked
up live via the bind mount — no rebuild). polymer has no local build, so just
re-pull:

```bash
podman image pull mcr.microsoft.com/devcontainers/javascript-node:24
systemctl --user restart polymer-dev-app
```

## Editing the units

Edit a file here, then:

```bash
~/Code/cn/gloo/quadlets/polymer/install.sh   # re-symlinks + daemon-reload
systemctl --user restart polymer-dev-app
```

You can preview the exact generated service with:

```bash
/usr/lib/systemd/system-generators/podman-system-generator --user --dryrun | sed -n '/polymer-dev-app.service/,/^$/p'
```

## Coexistence with the compose stack

The two stacks use completely separate names, so they never collide — but they
**cannot run at the same time** because both publish host ports 3000/3001. Pick
one:

```bash
# compose (existing):
~/Code/cn/gloo/dev polymer up        # ...then down before using the quadlet one

# quadlet (this):
systemctl --user start polymer-dev-app
```

## Known gap (matches compose)

S3/media is not wired up here, exactly as in the compose setup (the shared
`.env.local` points `S3_ENDPOINT` at `localhost:9000` and uses `rustfsadmin`
creds that don't match the local MinIO `minio`/`password`). The app boots fine
without it. If you want media working, the cleanest fix is env overrides on the
app unit (`S3_ENDPOINT=http://polymer_minio:9000`, `AWS_ACCESS_KEY_ID=minio`,
`AWS_SECRET_ACCESS_KEY=password`) — say the word and I'll add them.

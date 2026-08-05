# bee remote dev stacks — podman user-quadlets (gpl, polymer, buildspace)

This mirrors the **thinkpad's** rootless user-quadlet dev setup (the one that's
been "perfect") onto `bee`, so you can use bee as a remote dev machine for the
three Gloo/buildspace projects. Same container images, same dev-server.sh model,
same `keep-id` ownership semantics, same on-demand (no auto-start) behavior —
just delivered **NixOS-declaratively** and fronted by the **bees internal Caddy**
so you can reach the dev servers from your laptop over the Nebula overlay.

## Architecture

```
~/Gloo/360-gpl, ~/Gloo/360-polymer, ~/buildspace   cloned product repos on bee
~/.../hosts/bee/dev-quadlets/{gpl,polymer,buildspace}/   THIS — orchestration (tracked)
├── *.network / *.volume / *.container              quadlet input files
├── dev-server.sh                                   PID 1 of each app container
hosts/bee/dev-quadlets.nix                          NixOS module that wires it all up
hosts/bees/caddy/routes/internal/dev.caddy          bees Caddy → 10.10.0.12:<port>
```

The NixOS module (`hosts/bee/dev-quadlets.nix`):

1. Materializes the quadlet units + `dev-server.sh` read-only under
   `/etc/dev-quadlets/<project>/` (Nix store symlinks).
2. Symlinks the `*.container` / `*.volume` / `*.network` files into
   `~/.config/containers/systemd/` (the rootless user-quadlet search path) for
   `crussell`, then `systemctl --user daemon-reload`s.
3. Ships a `qd` wrapper (one script for all three projects).

So `nix run .#deploy -- bee` registers/updates everything — **no manual install
step, no `cn` checkout required on bee.** Linger is on for `crussell`, so the
user manager (and the user podman socket) is always up.

## What runs (per project)

| Project | App image | DB | S3 | App port(s) | Caddy hostname(s) |
| --- | --- | --- | --- | --- | --- |
| gpl | `devcontainers/javascript-node:22` | postgres:15 | minio | 3006 | `gpl.internal` |
| polymer | `devcontainers/javascript-node:24` | postgres:16 | minio | 3000, 3001 | `polymer.internal`, `admin360.internal` |
| buildspace | `oven/bun:1.3.14` | postgres:17 | minio (pinned) | 3000,3002–3006,3008,3010 | `bs-*.internal` (8) |

(All `*.internal.crussell.io` — abbreviated above.) All three app containers
run as **root (UID 0) inside the container** — in rootless podman that maps to
crussell on the host, so bind-mount artifacts (`node_modules`, `.next`, caches)
land crussell-owned. The thinkpad units use `UserNS=keep-id` for this, but
bee's rootless podman + native overlay breaks keep-id (recursive-userns
permission error), so bee runs `User=0` instead — same ownership outcome.

## Daily use (on bee, over SSH)

```bash
ssh -o IdentitiesOnly=yes crussell@10.10.0.12

qd gpl up              # or: systemctl --user start gpl-dev-app   (starts db+minio+app)
qd gpl status          # status of app + db + minio
qd gpl logs            # journalctl --user -u gpl-dev-app -f
qd gpl down            # stops app + db + minio (PartOf= cascade)

# same for:  qd polymer ...   |   qd buildspace ...
```

Then browse from your laptop (the bees Caddy terminates TLS and proxies to bee
over Nebula):

- **https://gpl.internal.crussell.io**
- **https://polymer.internal.crussell.io** / **https://admin360.internal.crussell.io**
- **https://bs-marketplace.internal.crussell.io** (+ `bs-runtime`, `bs-login`,
  `bs-docs`, `bs-studio`, `bs-super-admin`, `bs-registry`, `bs-jobs`)

You can also hit the published ports directly on bee if you're on the LAN/Nebula
(`http://192.168.20.105:3006` or `http://10.10.0.12:3006`) — rootless podman on
bee publishes to `0.0.0.0`.

### Port-collision rule

polymer (:3000) and buildspace marketplace (:3000) share a port; gpl (:3006) and
buildspace super-admin (:3006) share a port. **Only one of a colliding pair can
be running at a time** — otherwise the shared Caddy hostname proxies to
whichever app happens to be up. gpl + polymer are always safe together.

## First run (per project)

The first `start` installs deps inside the container against the live bind mount
and boots against a **fresh, empty** postgres. Once the app container is up,
push the schema:

```bash
# gpl
podman exec gpl-quadlet-app pnpm db:push
podman exec gpl-quadlet-app pnpm db:seed   # optional

# polymer
podman exec polymer-quadlet-app pnpm db:push
podman exec polymer-quadlet-app pnpm db:seed   # optional

# buildspace
podman exec buildspace-quadlet-app bun db:migrate
podman exec buildspace-quadlet-app bun db:seed   # optional; creates the super_admin below
```

(MinIO buckets are created automatically by each `dev-server.sh`.)

## Public-URL config for the Caddy front (one-time + per-IDP)

The apps ship assuming `localhost`. Behind the bees Caddy they need to know
their real `*.internal.crussell.io` origin. **gpl and polymer are already wired
in their `dev-server.sh`** (exported/inlined before `next dev`); buildspace has
no known URL env. Remaining steps are **external and manual**:

- **gpl — Hummingbird SSO:** register the new callback URI
  `https://gpl.internal.crussell.io/auth/hummingbird/callback` in the
  Hummingbird IDP (Salesforce/Google in `~/Gloo/360-gpl/.env.local` are
  unaffected; `BETTER_AUTH_URL`/`NEXT_PUBLIC_BETTER_AUTH_URL` are already
  exported to the Caddy origin in `dev-server.sh`).
- **polymer — WorkOS:** add both redirect URIs to the WorkOS dashboard:
  `https://polymer.internal.crussell.io/callback` and
  `https://admin360.internal.crussell.io/callback`. `WORKOS_COOKIE_DOMAIN` is
  exported to `.internal.crussell.io` so auth cookies are shared across the two
  subdomains.
- **buildspace:** no URL env at the compose level. If an app generates wrong
  absolute URLs through the `bs-*` hostnames, add the override inline at its
  launch in `dev-server.sh` (or via `apps/<app>/.env.local`).

> **SSH-tunnel fallback:** for an OAuth-heavy session where you don't want to
> touch any of the above, tunnel instead — `ssh -L 3006:localhost:3006
> crussell@10.10.0.12` then browse `http://localhost:3006`. The app still thinks
> it's on localhost, so every callback/cookie/absolute URL works unchanged.
> (Just don't combine a tunnel with the Caddy origin env — pick one access mode
> per session.)

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

## How it behaves (by design)

- **No auto-start on boot.** No unit has an `[Install]` section → nothing is
  enabled; stacks run only when you `start` them.
- **Dev server is PID 1, no auto-restart.** If a dev server crashes, the
  container stops so you can read the logs and `restart` it — no restart loop.
- **DB + MinIO data persist** in the `systemd-<project>-dev-db` /
  `systemd-<project>-dev-minio` volumes across stop/start.
- **Coexists with the rootful `buzz-relay` system quadlets** on bee — completely
  separate podman stores (root vs crussell).

## Differences from the thinkpad setup

- **Delivered by a NixOS module** (`hosts/bee/dev-quadlets.nix`) instead of
  per-project `install.sh` symlinks — no `cn` checkout needed on bee.
- **No SELinux** → the `:Z`/`:z` Volume suffixes from the thinkpad units are
  dropped.
- **Repo paths** use `/home/crussell` (not `/var/home/crussell`); buildspace
  lives at `~/buildspace` (not `~/Code/buildspace`).
- **`dev-server.sh` is Nix-managed** (bind-mounted from
  `/etc/dev-quadlets/<project>/`) and additionally exports the
  `*.internal.crussell.io` public URLs so the apps generate correct absolute
  URLs behind the bees Caddy.

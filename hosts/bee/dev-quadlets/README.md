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
| polymer | `devcontainers/javascript-node:24` | postgres:16 | minio | 3100→3000, 3101→3001 | `polymer.internal`, `admin360.internal` |
| buildspace | `oven/bun:1.3.14` | postgres:17 | minio (pinned) | 3200/3202–3206/3208/3210 → 3000/3002–3010 | `bs-*.internal` (8) |

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

### Port scheme (all three projects run simultaneously)

bee also runs the production **buzz-relay** (owns bee's `:3000` and `:5000`), so
the dev stacks publish on **offset host ports** that never collide with buzz-relay
or with each other: **gpl** uses `:3006`, **polymer** uses the `:31xx` block
(container `:3000`/`:3001`), **buildspace** uses the `:32xx` block (container
`:3000`/`:3002`–`:3010`). The Caddy routes point at these host ports; the apps
still listen on their repo-defined ports *inside* the container, so
`NEXT_PUBLIC_BASE_URL` / `BETTER_AUTH_URL` etc. are unaffected. Because the three
projects use disjoint host-port ranges, **gpl + polymer + buildspace can all run
on bee at the same time** (unlike the thinkpad, where polymer+buildspace collide
on `:3000`).

> **RAM is the real limiter, not ports.** The dev compilers are memory-heavy
> (polymer's Turbopack app alone peaks ~20 GB; buildspace's turbo runs 8+ apps;
> bee has 27 GB + zram swap). Running polymer + buildspace at once can OOM-kill
> a dev server (native segfault). For stability, run **one heavy project at a
> time** (gpl is light; polymer and buildspace are heavy). `qd <project> restart`
> brings a crashed stack back.

## First run (per project)

> **One-time: clear host-installed `node_modules`.** Each repo was previously
> run on bee's **host** (pnpm/bun via Nix), so its `node_modules/` is
> incompatible with the container's toolchain — `pnpm exec`/turbo will fail with
> a `confirmModulesPurge`/reconcile prompt or native errors. Before the first
> `qd <project> up`, delete it once so `dev-server.sh` does a fresh in-container
> install:
> ```bash
> rm -rf ~/Gloo/360-gpl/node_modules      # or 360-polymer, or ~/buildspace
> ```
> (This was already done during initial bring-up — only repeat if a repo's deps
> were touched on the host again.)

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
in their `dev-server.sh`**; buildspace has no known URL env. Remaining steps are
**external and manual** (only for polymer/buildspace — gpl needs nothing):

- **gpl — local dev auth (needs a one-line gpl-code change):** gpl's
  `hummingbird-login.ts` selects Hummingbird SSO vs. a local dev auth fallback.
  It used to key that choice on `BETTER_AUTH_URL` being localhost, which broke
  behind the Caddy (a real origin flipped SSO on; an empty one made
  `auth-client.ts` fall back to `localhost:3006`). The fix in the gpl repo:
  `shouldUseLocalAuthFallback()` returns true whenever
  `NODE_ENV === "development"` (Next.js's own "is `next dev` running" signal) —
  then `dev-server.sh` sets `BETTER_AUTH_URL`/`NEXT_PUBLIC_BETTER_AUTH_URL` to
  `https://gpl.internal.crussell.io` so the local dev auth runs with correct
  proxied URLs. No Hummingbird setup. Behind Caddy this ALSO needs
  `allowedDevOrigins` in gpl's `next.config.ts` (Next.js blocks its dev/HMR
  channel for non-localhost origins, which prevents client hydration without it).
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

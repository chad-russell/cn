# bee remote dev stacks — podman user-quadlets (gpl, polymer, buildspace)

This mirrors the **thinkpad's** rootless user-quadlet dev setup onto `bee`, so
you can use bee as a remote dev machine for the three Gloo/buildspace projects.
Same container images, same `dev-server.sh` model, same on-demand (no auto-start)
behavior — delivered **NixOS-declaratively** and reached over **SSH port-forward
tunnels** so the apps see `localhost` exactly as they do on the thinkpad.

> **Why tunnels, not a reverse proxy.** Next.js dev servers hard-code localhost
> assumptions: the HMR/dev channel is restricted to localhost origins (Next.js
> `allowedDevOrigins`), and gpl/polymer auth clients fall back to `localhost:3000`
> / `3006`. Fronting them with a non-localhost proxy (Caddy) breaks hydration and
> auth and would require editing the product repos (incl. personal hostnames — a
> no-go for the team repos). SSH-forwarding `localhost` sidesteps all of it: zero
> product-repo changes, every callback/cookie/HMR URL works unchanged.

## Architecture

```
~/Gloo/360-gpl, ~/Gloo/360-polymer, ~/buildspace   cloned product repos on bee
~/.../hosts/bee/dev-quadlets/{gpl,polymer,buildspace}/   THIS — orchestration (tracked)
├── *.network / *.volume / *.container              quadlet input files
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
3. Ships a `qd` wrapper on bee (one script for all three projects).

So `nix run .#deploy -- bee` registers/updates everything — **no manual install
step, no `cn` checkout required on bee.** Linger is on for `crussell`, so the
user manager (and the user podman socket) is always up.

## What runs (per project)

| Project | App image | DB | S3 | Tunnel ports (laptop `localhost:`) |
| --- | --- | --- | --- | --- |
| gpl | `devcontainers/javascript-node:22` | postgres:15 | minio | `3006` |
| polymer | `devcontainers/javascript-node:24` | postgres:16 | minio | `3000` (polymer), `3001` (admin360) |
| buildspace | `oven/bun:1.3.14` | postgres:17 | minio (pinned) | `3000`, `3002`, `3003`, `3004`, `3005`, `3006`, `3008`, `3010` |

All three app containers run as **root (UID 0) inside the container** — in
rootless podman that maps to crussell on the host, so bind-mount artifacts
(`node_modules`, `.next`, caches) land crussell-owned. The thinkpad units use
`UserNS=keep-id` for this, but bee's rootless podman + native overlay breaks
keep-id (recursive-userns permission error), so bee runs `User=0` instead — same
ownership outcome.

## Daily use

**1. Start the stack on bee** (db + minio + app, on-demand — nothing auto-starts):

```bash
ssh -o IdentitiesOnly=yes crussell@10.10.0.12
qd gpl up              # or: systemctl --user start gpl-dev-app
qd gpl status          # status of app + db + minio
qd gpl logs            # journalctl --user -u gpl-dev-app -f
qd gpl down            # stops app + db + minio (PartOf= cascade)
# same for:  qd polymer ...   |   qd buildspace ...
```

**2. Open the tunnel from your laptop** and browse `localhost`:

```bash
cjust dev-up gpl          # start gpl on bee AND open the tunnel (one shot)
# — or, if the stack is already running on bee —
cjust dev-tunnel gpl          # then browse http://localhost:3006
cjust dev-tunnel polymer      # http://localhost:3000 + http://localhost:3001
cjust dev-tunnel buildspace   # 8 ports: 3000,3002–3006,3008,3010
```

Ctrl-C closes a tunnel. `cjust dev-tunnel <project>` forwards the **same** ports
you'd use on the thinkpad onto bee's offset published ports; the apps can't tell
the difference from local dev.

### Port scheme

bee also runs the production **buzz-relay** (owns bee's `:3000` and `:5000`), so
the dev stacks publish on **offset host ports** on bee that never collide with
buzz-relay or each other: gpl `:3006`, polymer `:3100`/`:3101` (container
`:3000`/`:3001`), buildspace `:32xx` (container `:3000`/`:3002`–`:3010`). The
`cjust dev-tunnel` (and `cjust dev-up`) re-maps those onto the thinkpad-standard localhost ports
(`:3000`, `:3006`, …) so nothing in the apps or your muscle memory changes.
Because the three projects use disjoint host-port ranges on bee, all three *can*
run simultaneously — see the RAM caveat below.

> **RAM is the real limiter, not ports.** The dev compilers are memory-heavy
> (polymer's Turbopack app alone peaks ~20 GB; buildspace's turbo runs 8+ apps;
> bee has 27 GB + zram swap). Running polymer + buildspace at once can OOM-kill a
> dev server (native segfault). For stability, run **one heavy project at a time**
> (gpl is light; polymer and buildspace are heavy). `qd <project> restart` brings
> a crashed stack back.

## First run (per project)

> **One-time: clear host-installed `node_modules`.** Each repo was previously run
> on bee's **host** (pnpm/bun via Nix), so its `node_modules/` is incompatible
> with the container's toolchain — `pnpm exec`/turbo will fail with a
> `confirmModulesPurge`/reconcile prompt or native errors. Before the first
> `qd <project> up`, delete it once so `dev-server.sh` does a fresh in-container
> install:
> ```bash
> rm -rf ~/Gloo/360-gpl/node_modules      # or 360-polymer, or ~/buildspace
> ```

The first `start` installs deps inside the container against the live bind mount
and boots against a **fresh, empty** postgres. Once the app container is up, push
the schema:

```bash
# gpl
podman exec gpl-quadlet-app pnpm db:push
podman exec gpl-quadlet-app pnpm db:seed   # optional; creates admin@gpl.org/admin123

# polymer
podman exec polymer-quadlet-app pnpm db:push
podman exec polymer-quadlet-app pnpm db:seed   # optional

# buildspace
podman exec buildspace-quadlet-app bun db:migrate
podman exec buildspace-quadlet-app bun db:seed   # optional; creates the super_admin below
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
  `/etc/dev-quadlets/<project>/`); otherwise identical to the thinkpad — no
  proxy/auth overrides, because the SSH tunnel makes the app see `localhost`.
- **App containers run as `User=0`** (not `UserNS=keep-id`) — bee's rootless
  overlay breaks keep-id; `User=0` gives the same crussell-owned bind mounts.

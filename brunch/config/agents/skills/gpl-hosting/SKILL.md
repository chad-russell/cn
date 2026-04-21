---
name: gpl-hosting
description: Describes how GPL is hosted on hub for local development, including the GPL app, Hummingbird dependencies, systemd units, routes, logs, and database workflows.
---

# GPL Hosting

Use this skill when working on the local GPL stack in this repository.

## Repo And Runtime Layout

- Infra repo: `~/Code/cn`
- GPL repo: `~/Gloo/360-gpl`
- Hummingbird repo: `~/Gloo/360-hummingbird`
- Control plane repo: `~/Gloo/gloo-control-plane`
- Brunch target: `hub`

Relevant Brunch config lives in:

- `~/Code/cn/brunch/config/brunch.bri`
- `~/Code/cn/brunch/config/hosts/hub/index.bri`
- `~/Code/cn/brunch/config/hosts/hub/dev-stacks.bri`
- `~/Code/cn/brunch/config/hosts/hub/gloo/render-runtime-env.sh`

## Main Units

- Stack entrypoint: `gloo-gpl.service`
- GPL deps and DB bootstrap: `gloo-gpl-deps.service`
- GPL app: `gloo-gpl-app.service`
- Hummingbird stack: `gloo-hummingbird.service`
- Hummingbird API: `gloo-hummingbird-api.service`
- Hummingbird web: `gloo-hummingbird-web.service`
- Shared infra: `dev-postgres.service`, `gloo-rustfs.service`, `gloo-buckets.service`, `gloo-host-gateway.service`

Start or stop everything for GPL with:

```bash
systemctl --user start gloo-gpl.service
systemctl --user stop gloo-gpl.service
systemctl --user restart gloo-gpl.service
```

Restart a single piece with:

```bash
systemctl --user restart gloo-gpl-app.service
systemctl --user restart gloo-hummingbird-api.service
systemctl --user restart gloo-hummingbird-web.service
```

## Routes

Internal hosts are routed through Caddy on `hub`:

- `https://gpl.internal.crussell.io`
- `https://hb-api.internal.crussell.io`
- `https://hb-web.internal.crussell.io`
- `https://polymer.internal.crussell.io`
- `https://rustfs.internal.crussell.io`
- `https://rustfs-console.internal.crussell.io`
- `https://pgadmin.internal.crussell.io`

Hub-specific Brunch target composition lives at:

- `~/Code/cn/brunch/config/hosts/hub/index.bri`
- `~/Code/cn/brunch/config/hosts/hub/dev-stacks.bri`

Important: after `brunch apply`, route changes usually require a full Caddy container restart, not just a reload, because the container bind-mounts the current Brunch generation.

```bash
brunch apply ./config --target hub
sudo systemctl restart caddy.service
```

## Environment Files

Browser-facing and service env values live in:

- `~/Gloo/gloo-control-plane/envs/gpl.env`
- `~/Gloo/gloo-control-plane/envs/hb-api.env`
- `~/Gloo/gloo-control-plane/envs/hb-web.env`
- `~/Gloo/360-hummingbird/web/.env`
- `~/Gloo/360-hummingbird/api/.env`

When debugging hostname or mixed-content issues, check these first.

## Logs And Status

Use systemd logs first:

```bash
systemctl --user status gloo-gpl.service --no-pager
systemctl --user status gloo-gpl-app.service --no-pager
systemctl --user status gloo-hummingbird-api.service --no-pager
systemctl --user status gloo-hummingbird-web.service --no-pager

journalctl --user -u gloo-gpl-app.service -n 200 --no-pager
journalctl --user -u gloo-hummingbird-api.service -n 200 --no-pager
journalctl --user -u gloo-hummingbird-web.service -n 200 --no-pager
```

Container names match the unit names without `.service`:

- `gloo-gpl-app`
- `gloo-hummingbird-api`
- `gloo-hummingbird-web`

Useful container commands:

```bash
podman logs --since 10m gloo-gpl-app
podman logs --since 10m gloo-hummingbird-api
podman logs --since 10m gloo-hummingbird-web
```

## Database Workflows

GPL uses `dev-postgres` and the GPL app container can reach the database via `DATABASE_URL`.

Common commands:

```bash
podman exec gloo-gpl-app /bin/sh -lc 'cd /workspace && corepack pnpm db:push'
podman exec gloo-gpl-app /bin/sh -lc 'cd /workspace && corepack pnpm db:seed'
podman exec gloo-gpl-app /bin/sh -lc 'cd /workspace && corepack pnpm db:reset'
```

`gloo-gpl-deps.service` now handles both dependency install and GPL schema bootstrap with `db:push`.

## Hummingbird Seed Workflow

GPL auth depends on Hummingbird data and roles.

Run the current Hummingbird seed inside the API container with:

```bash
podman exec gloo-hummingbird-api /bin/sh -lc 'cd /workspace/api && pnpm run seed'
```

That restores the dev dump, runs migrations, and creates the dev users.

Useful seeded login:

- Hummingbird: `admin@mail.com` / `password`

If GPL login fails with missing permissions, check Hummingbird roles first.

## GPL Seed Workflow

GPL starter data is a separate seed from Hummingbird:

```bash
podman exec gloo-gpl-app /bin/sh -lc 'cd /workspace && corepack pnpm db:seed'
```

Useful seeded GPL logins:

- `admin@gpl.org` / `admin123`
- `viewer@gpl.org` / `viewer123`

The GPL seed clears existing GPL project-related data before inserting starter data.

## Typical Dev Loop

1. Edit code in `~/Gloo/360-gpl` or `~/Gloo/360-hummingbird`.
2. If env or Brunch-managed config changed, run:

```bash
cd ~/Code/cn/brunch
brunch apply ./config --target hub
```

3. Restart affected services.
4. If routes changed, run `sudo systemctl restart caddy.service`.
5. Watch logs while reproducing.

## Known Local Details

- GPL depends on Hummingbird for auth and project sync workflows.
- The external hostname logic in GPL needs `*.internal.crussell.io` host headers to be preserved by Caddy.
- Flat subdomains are required because the wildcard cert only covers one level under `internal.crussell.io`.

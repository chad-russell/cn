---
name: buildspace-hosting
description: Describes how Buildspace is hosted on hub for local development, including stack units, routes, logs, environment files, and database/bootstrap workflows.
---

# Buildspace Hosting

Use this skill when working on the local Buildspace stack in this repository.

## Repo And Runtime Layout

- Infra repo: `~/Code/cn`
- Buildspace repo: `~/Code/bs/buildspace`
- Brunch target: `hub`

Brunch config lives in:

- `~/Code/cn/brunch/config/brunch.bri`
- `~/Code/cn/brunch/config/modules/buildspace.bri`
- `~/Code/cn/brunch/config/modules/buildspace/buildspace.caddy`
- `~/Code/cn/brunch/config/modules/buildspace/buildspace.env.example`

## Main Units

- Stack entrypoint: `buildspace.service`
- Dependency install: `buildspace-deps.service`
- Database bootstrap: `buildspace-bootstrap.service`
- Marketplace: `buildspace-marketplace.service`
- Login: `buildspace-login.service`
- Runtime/API: `buildspace-runtime.service`
- Studio: `buildspace-studio.service`
- Docs: `buildspace-docs.service`
- Super-admin: `buildspace-super-admin.service`
- Jobs worker: `buildspace-jobs.service`
- Shared DB infra: `dev-postgres.service`

Start or stop the full stack with:

```bash
systemctl --user start buildspace.service
systemctl --user stop buildspace.service
systemctl --user restart buildspace.service
```

Bootstrap when dependencies, schema, or seed data need to be refreshed:

```bash
systemctl --user start buildspace-deps.service
systemctl --user start buildspace-bootstrap.service
```

Restart one app when only a single surface changed:

```bash
systemctl --user restart buildspace-marketplace.service
systemctl --user restart buildspace-login.service
systemctl --user restart buildspace-runtime.service
systemctl --user restart buildspace-studio.service
systemctl --user restart buildspace-docs.service
systemctl --user restart buildspace-super-admin.service
systemctl --user restart buildspace-jobs.service
```

## Routes

Buildspace internal hosts are:

- `https://buildspace.internal.crussell.io`
- `https://bs-login.internal.crussell.io`
- `https://bs-creator.internal.crussell.io`
- `https://bs-api.internal.crussell.io`
- `https://bs-docs.internal.crussell.io`
- `https://bs-admin.internal.crussell.io`
- `https://bs-jobs.internal.crussell.io`

The Brunch-managed route file is:

- `~/Code/cn/brunch/config/modules/buildspace/buildspace.caddy`

After route changes:

```bash
cd ~/Code/cn/brunch
brunch apply ./config --target hub
sudo systemctl restart caddy.service
```

## Environment Files

Buildspace expects these local files on the host:

- repo env: `~/Code/bs/buildspace/.env`
- systemd overrides: `~/.config/buildspace/buildspace.env`
- managed example: `~/.config/buildspace/buildspace.env.example`

If a host, cookie, redirect, or trusted-origin issue appears, compare the real env files to the managed example first.

## Logs And Status

Use systemd status and logs:

```bash
systemctl --user status buildspace.service --no-pager
systemctl --user status buildspace-bootstrap.service --no-pager
systemctl --user status buildspace-login.service --no-pager
systemctl --user status buildspace-runtime.service --no-pager

journalctl --user -u buildspace-bootstrap.service -n 200 --no-pager
journalctl --user -u buildspace-marketplace.service -n 200 --no-pager
journalctl --user -u buildspace-login.service -n 200 --no-pager
journalctl --user -u buildspace-runtime.service -n 200 --no-pager
journalctl --user -u buildspace-studio.service -n 200 --no-pager
journalctl --user -u buildspace-super-admin.service -n 200 --no-pager
journalctl --user -u buildspace-jobs.service -n 200 --no-pager
```

## Database Workflow

`buildspace-bootstrap.service` is the canonical DB setup path on this machine. It:

- reads `DATABASE_URL` from the repo `.env`
- creates the DB role and DB if needed
- enables `pgcrypto`
- runs package-local migrations
- runs the Buildspace seed

If you need to run DB commands manually, the Brunch module currently uses Bun from `~/.bun/bin`.

Relevant manual command shape:

```bash
cd ~/Code/bs/buildspace/packages/db
~/.bun/bin/bun --env-file=../../.env run db:migrate
~/.bun/bin/bun --env-file=../../.env run db:seed
```

## Typical Dev Loop

1. Edit code in `~/Code/bs/buildspace`.
2. If Brunch-managed config changed, run:

```bash
cd ~/Code/cn/brunch
brunch apply ./config --target hub
```

3. Restart the affected app service or the full `buildspace.service` stack.
4. If route files changed, run `sudo systemctl restart caddy.service`.
5. If schema or seed state is involved, rerun `buildspace-bootstrap.service`.

## Known Local Details

- Buildspace relies on the shared `dev-postgres.service` container from the dev-infra Brunch module.
- The stack is split into several independent user services, but `buildspace.service` is the one-command entrypoint.
- Flat internal subdomains are used because the wildcard cert only covers one subdomain level under `internal.crussell.io`.

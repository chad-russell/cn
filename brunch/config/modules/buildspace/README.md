# Buildspace Brunch Module

This module is intended for the `hub` Brunch target.

It manages:

- `buildspace.service` as the stack entrypoint
- Buildspace app and worker user services
- an internal Caddy route snippet for the Buildspace dev hosts
- `~/.config/buildspace/buildspace.env.example`

It depends on the shared dev-infra module for `dev-postgres.service`.

## Manual Prerequisites

The module assumes these are created manually on the target host:

- repo clone at `~/Code/bs/buildspace`
- repo env file at `~/Code/bs/buildspace/.env`
- systemd env overrides at `~/.config/buildspace/buildspace.env`

Start from the managed example file:

- `~/.config/buildspace/buildspace.env.example`

## Apply And Start

Apply the hub profile:

```bash
brunch apply ./config --target hub
```

Run dependency install and database setup when needed:

```bash
systemctl --user start buildspace-deps.service
systemctl --user start buildspace-bootstrap.service
```

`buildspace-bootstrap.service` prepares the database role/database from `DATABASE_URL`, enables `pgcrypto`, then runs the package-local migrations and seed.

Start the whole stack with one command:

```bash
systemctl --user start buildspace.service
```

## Internal Routes

The managed Caddy snippet exposes these hosts on `hub`:

- `buildspace.internal.crussell.io`
- `login.buildspace.internal.crussell.io`
- `creator.buildspace.internal.crussell.io`
- `api.buildspace.internal.crussell.io`
- `docs.buildspace.internal.crussell.io`
- `super-admin.buildspace.internal.crussell.io`
- `jobs.buildspace.internal.crussell.io`

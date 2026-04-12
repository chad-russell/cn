# Gloo Brunch Module

This module is intended for the `hub` Brunch target.

It manages:

- Gloo quadlets for app containers, build images, and volumes
- stack entrypoint services:
  - `gloo-gpl.service`
  - `gloo-hummingbird.service`
  - `gloo-polymer.service`
  - `gloo-admin.service`
  - `gloo-all.service`
- helper services for host gateway env, bucket init, and dependency bootstrapping
- an internal Caddy route snippet for the Gloo dev hosts

It depends on the shared dev-infra module for:

- `dev-network.service`
- `dev-postgres.service`

## Manual Prerequisites

- repo clone at `~/Gloo/gloo-control-plane`
- repo clone at `~/Gloo/360-gpl`
- repo clone at `~/Gloo/360-hummingbird`
- repo clone at `~/Gloo/360-polymer`
- required env files under `~/Gloo/gloo-control-plane/envs/`

## Apply And Start

```bash
brunch apply ./config --target hub
```

Start individual stacks:

```bash
systemctl --user start gloo-gpl.service
systemctl --user start gloo-hummingbird.service
systemctl --user start gloo-polymer.service
systemctl --user start gloo-admin.service
```

Or start everything:

```bash
systemctl --user start gloo-all.service
```

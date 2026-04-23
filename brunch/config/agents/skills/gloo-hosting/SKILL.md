---
name: gloo-hosting
description: Operate the Gloo dev stack on hub. Use when working in 360-gpl, 360-hummingbird, 360-polymer, or the old gloo-control-plane and the task involves app start/stop, logs, env/secrets, systemd units, compose infra, or local dev routing.
---

# Gloo Dev Stack Hosting

The Gloo stack on `hub` uses:

- **Podman Compose** for shared infra only
- **systemd user services** for host dev servers (managed by brunch)
- **age-encrypted secrets** rendered to runtime env files
- **Caddy** as the shared reverse proxy

## Quick start

```bash
just -f ~/Code/cn/servers/hub/dev-stacks/gloo/Justfile up
just -f ~/Code/cn/servers/hub/dev-stacks/gloo/Justfile stop
```

For first-time setup, use `bootstrap-all` instead of `up`.

## Infra

Compose file:

```text
~/Code/cn/servers/hub/dev-stacks/gloo/compose.yaml
```

Services:
- postgres on `127.0.0.1:5433`
- rustfs on `127.0.0.1:9000`
- rustfs console on `127.0.0.1:9001`
- pgadmin on `127.0.0.1:5050`

Infra lifecycle is managed via the `gloo-infra.target` systemd target, which starts compose, creates databases, and creates S3 buckets:

```bash
systemctl --user start gloo-infra.target
systemctl --user status gloo-infra.target
journalctl --user -u gloo-infra-up.service
journalctl --user -u gloo-init-db.service
journalctl --user -u gloo-init-buckets.service
```

Or use the Justfile shortcuts:

```bash
just -f ~/Code/cn/servers/hub/dev-stacks/gloo/Justfile infra-up
just -f ~/Code/cn/servers/hub/dev-stacks/gloo/Justfile infra-down
just -f ~/Code/cn/servers/hub/dev-stacks/gloo/Justfile infra-logs
```

## App services

Systemd user units are managed declaratively via brunch (`brunch apply ./config --target hub`).
Do **not** install or symlink unit files manually — brunch handles creation, updates, and cleanup.

### Individual services

| Unit | Port | Project |
|---|---:|---|
| `gloo-gpl.service` | 3106 | `~/Gloo/360-gpl` |
| `gloo-hb-api.service` | 8000 | `~/Gloo/360-hummingbird` |
| `gloo-hb-web.service` | 3100 | `~/Gloo/360-hummingbird` |
| `gloo-storyhub.service` | 3007 | `~/Gloo/360-hummingbird/storyhub` |
| `gloo-storyhub-worker.service` | 8001 | `~/Gloo/360-hummingbird` |
| `gloo-polymer.service` | 3001 | `~/Gloo/360-polymer/apps/polymer` |

All app services depend on `gloo-infra.target` and will wait for infra to be ready.

### Grouping targets

| Target | Starts |
|---|---|
| `gloo-infra.target` | compose up + init-db + init-buckets |
| `gloo-hummingbird.target` | `gloo-hb-api.service` + `gloo-hb-web.service` |
| `gloo-storyhub.target` | `gloo-storyhub.service` + `gloo-storyhub-worker.service` |
| `gloo-all.target` | all Gloo app services |

Examples:

```bash
systemctl --user start gloo-gpl.service
systemctl --user start gloo-hummingbird.target
systemctl --user start gloo-storyhub.target
systemctl --user start gloo-polymer.service
systemctl --user stop gloo-polymer.service
systemctl --user restart gloo-hb-api.service
```

## Logs and status

```bash
systemctl --user status gloo-polymer.service
journalctl --user -u gloo-polymer.service -n 100
journalctl --user -u gloo-polymer.service -f
```

For grouped stacks, inspect the member units individually.

## Runtime env / secrets

Non-secret config:

```text
~/Code/cn/servers/hub/dev-stacks/gloo/host-envs/*.env
```

Encrypted secrets:

```text
~/Code/cn/servers/hub/dev-stacks/gloo/secrets/gloo-secrets.env.age
```

At service start, `render-runtime-env.sh` writes a merged runtime file to:

```text
/run/user/$UID/gloo/<service>.env
```

That file is then sourced by each service's Brioche runnable (defined in `brunch/config/hosts/hub/dev-stacks.bri`) before launching the app.

## Bootstrap

Per-service bootstrap scripts are in `~/Code/cn/servers/hub/dev-stacks/gloo/scripts/`:
- `bootstrap-gpl.sh` — push schema + seed
- `bootstrap-hb-api.sh` — seed data (uses psql wrapper)
- `bootstrap-storyhub.sh` — seed data
- `bootstrap-polymer.sh` — push schema + seed

Use the Justfile for convenience:

```bash
just -f ~/Code/cn/servers/hub/dev-stacks/gloo/Justfile bootstrap-gpl
just -f ~/Code/cn/servers/hub/dev-stacks/gloo/Justfile bootstrap-all
```

## Caddy routes

Routes are defined in `~/Code/cn/servers/hub/caddy/routes/internal/gloo.caddy`:

| Host | Upstream |
|---|---|
| `gpl.internal.crussell.io` | `127.0.0.1:3106` |
| `hb-api.internal.crussell.io` | `127.0.0.1:8000` |
| `hb-web.internal.crussell.io` | `127.0.0.1:3100` |
| `storyhub.internal.crussell.io` | `127.0.0.1:3007` |
| `polymer.internal.crussell.io` | `127.0.0.1:3001` |
| `rustfs.internal.crussell.io` | `127.0.0.1:9000` |
| `rustfs-console.internal.crussell.io` | `127.0.0.1:9001` |
| `pgadmin.internal.crussell.io` | `127.0.0.1:5050` |

Reload Caddy after config edits:

```bash
sudo podman exec systemd-caddy caddy validate --config /etc/caddy/Caddyfile
sudo podman exec systemd-caddy caddy reload --config /etc/caddy/Caddyfile
```

## Important notes

- All services use linuxbrew Node 24 for consistency.
- Caddy is **separate**. App services only bind localhost ports.
- Polymer should use Turbopack unless there is a concrete host-level issue being debugged.
- Flat subdomains are required because the wildcard cert only covers one level under `internal.crussell.io`.

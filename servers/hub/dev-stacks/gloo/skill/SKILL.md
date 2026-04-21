---
name: gpl-hosting
description: Operate the Gloo dev stack on hub. Use when working in 360-gpl, 360-hummingbird, 360-polymer, or the old gloo-control-plane and the task involves app start/stop, logs, env/secrets, systemd units, compose infra, or local dev routing.
---

# Gloo Dev Stack Hosting

The Gloo stack on `hub` uses:

- **Podman Compose** for shared infra only
- **systemd user services** for host dev servers
- **age-encrypted secrets** rendered to runtime env files
- **Caddy** as the shared reverse proxy

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

Commands:

```bash
podman compose -f ~/Code/cn/servers/hub/dev-stacks/gloo/compose.yaml up -d
podman compose -f ~/Code/cn/servers/hub/dev-stacks/gloo/compose.yaml down
podman compose -f ~/Code/cn/servers/hub/dev-stacks/gloo/compose.yaml logs -f
~/Code/cn/servers/hub/dev-stacks/gloo/init-db.sh
~/Code/cn/servers/hub/dev-stacks/gloo/init-buckets.sh
```

## App services

Checked-in unit files live in:

```text
~/Code/cn/servers/hub/dev-stacks/gloo/systemd/units/
```

Install / refresh them with:

```bash
~/Code/cn/servers/hub/dev-stacks/gloo/install-user-units.sh
```

### Individual services

| Unit | Port | Project |
|---|---:|---|
| `gloo-gpl.service` | 3106 | `~/Gloo/360-gpl` |
| `gloo-hb-api.service` | 8000 | `~/Gloo/360-hummingbird` |
| `gloo-hb-web.service` | 3100 | `~/Gloo/360-hummingbird` |
| `gloo-storyhub.service` | 3007 | `~/Gloo/360-hummingbird/storyhub` |
| `gloo-storyhub-worker.service` | 8001 | `~/Gloo/360-hummingbird` |
| `gloo-polymer.service` | 3001 | `~/Gloo/360-polymer/apps/polymer` |

### Grouping targets

| Target | Starts |
|---|---|
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

This is the preferred interface for humans and AI agents.

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

That file is then sourced by `run-service.sh` before launching the app.

## Important notes

- Infra is **not** auto-started by app services. Start compose first.
- Caddy is **separate**. App services only bind localhost ports.
- `storyhub-worker` requires `bun` on host.
- Polymer requires Homebrew Node 24.
- Polymer should use Turbopack unless there is a concrete host-level issue being debugged.

## Caddy routes

| Host | Upstream |
|---|---|
| `gpl.internal.crussell.io` | `127.0.0.1:3106` |
| `hb-api.internal.crussell.io` | `127.0.0.1:8000` |
| `hb-web.internal.crussell.io` | `127.0.0.1:3100` |
| `storyhub.internal.crussell.io` | `127.0.0.1:3007` |
| `polymer.internal.crussell.io` | `127.0.0.1:3001` |

Reload Caddy after config edits:

```bash
sudo podman exec systemd-caddy caddy validate --config /etc/caddy/Caddyfile
sudo podman exec systemd-caddy caddy reload --config /etc/caddy/Caddyfile
```

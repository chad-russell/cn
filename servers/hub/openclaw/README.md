# OpenClaw on hub

This service runs OpenClaw in a dedicated rootless Podman environment under its
own `openclaw` system user.

## Goals

- Keep OpenClaw isolated from the main `crussell` user and other hub services.
- Limit host filesystem access to `/srv/openclaw/*`.
- Allow outbound internet access.
- Expose the Control UI internally at `openclaw.internal.crussell.io`.
- Allow OpenClaw to create sandbox and browser containers through the
  `openclaw` user's rootless Podman socket.

## Layout

Host paths:

- `/srv/openclaw/config` - OpenClaw config, sessions, credentials, logs, media
- `/srv/openclaw/workspace` - main agent workspace
- `/srv/openclaw/sandboxes` - sandbox workspaces used by tool containers

Container mounts:

- `/srv/openclaw/config` -> `/home/node/.openclaw`
- `/srv/openclaw/workspace` -> `/srv/openclaw/workspace`
- `/srv/openclaw/sandboxes` -> `/srv/openclaw/sandboxes`
- `/run/user/<openclaw-uid>/podman/podman.sock` -> `/var/run/docker.sock`

The sandbox and workspace paths are mounted at the same absolute paths used in
`openclaw.json` so that bind mounts created through the Podman API socket refer
to real host paths.

## Files

- `setup-openclaw.sh` - one-time host setup and deployment helper
- `openclaw.container.in` - rootless Quadlet template for the dedicated user
- `openclaw.json` - baseline OpenClaw config
- `openclaw.env.example` - env template for gateway auth, Telegram, and model keys
- `images/` - local Containerfiles used to build the gateway, sandbox, and sandbox browser images

## Initial deploy

Run as a privileged user on `hub`:

```bash
./servers/hub/openclaw/setup-openclaw.sh
```

That script:

- creates the `openclaw` system user if needed
- enables lingering and the `openclaw` user's `podman.socket`
- creates `/srv/openclaw/{config,workspace,sandboxes}`
- installs `openclaw.json` and a generated `.env`
- builds the three required images in the `openclaw` user's rootless Podman store
- installs the Quadlet and starts the service

## Secrets and config

Environment lives at `/srv/openclaw/config/.env`.

At minimum, set:

- `OPENCLAW_GATEWAY_TOKEN`
- `TELEGRAM_BOT_TOKEN`
- one or more model-provider credentials such as `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, or `GROQ_API_KEY`

The setup script generates `OPENCLAW_GATEWAY_TOKEN` automatically if missing.

Config lives at `/srv/openclaw/config/openclaw.json` and is mounted into the
container as `/home/node/.openclaw/openclaw.json`.

## Service management

```bash
sudo systemctl --machine openclaw@ --user status openclaw.service
sudo journalctl --machine openclaw@ --user -u openclaw.service -f
sudo systemctl --machine openclaw@ --user restart openclaw.service
```

## Reverse proxy

`servers/hub/caddy/Caddyfile` routes `openclaw.internal.crussell.io` to
`127.0.0.1:30110`.

## Notes

- OpenClaw gateway auth is enforced by `OPENCLAW_GATEWAY_TOKEN`.
- Device pairing still applies for remote browser sessions.
- The Podman socket mount is a deliberate trust boundary. OpenClaw can control
  containers as the `openclaw` user, so keep that user scoped only to
  `/srv/openclaw/*`.

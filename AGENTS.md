# AGENTS.md

This is the root navigation and operating guide for this personal infrastructure repository.

## Repository Overview

Use this file for global context. For implementation details, open the subsystem docs directly.

### Core Infrastructure Docs

| Area | Doc | Purpose |
|------|-----|---------|
| Nebula mesh VPN | `nebula/README.md` | Overlay topology, cert model, deploy/update workflows |
| Public ingress gateway | `servers/gateway/README.md` | Hetzner nginx SSL passthrough to hub over Nebula |
| Hub migration history | `servers/hub/MIGRATION.md` | Swarm → Quadlets migration context and historical decisions |

### Host and Service Docs

| Area | Doc | Purpose |
|------|-----|---------|
| AI host (`bees`) | `servers/ai/README.md` | llama.cpp + llama-swap operations |
| NAS monitoring agent | `servers/nas/README.md` | Beszel agent deployment on TrueNAS |
| Uptime monitoring | `servers/hub/peekaping/README.md` | Declarative monitor config and sync flow |
| Desktop config tooling | `brunch/README.md` | Brunch/Brioche desktop generation management |

### Config-First Directories (No README Yet)

- `servers/hub/quadlets/containers/` - Rootless Podman Quadlets for hub services
- `servers/hub/caddy/Caddyfile` - Caddy reverse proxy routes
- `servers/media/quadlets/` - Media stack containers on `media`

## Current Architecture

```text
                              Internet
                                  │
                    ┌─────────────▼─────────────┐
                    │      Hetzner VPS          │
                    │  178.156.171.212          │
                    │  (nginx: SSL passthrough) │
                    │  Nebula: 10.10.0.2        │
                    └─────────────┬─────────────┘
                                  │ Nebula VPN
┌─────────────────────────────────▼──────────────────────────────┐
│                              hub                               │
│              (192.168.20.105 - this machine)                   │
│                     Nebula split identity:                     │
│                     • 10.10.0.1 local lighthouse               │
│                     • 10.10.0.6 host/services endpoint         │
│                                                                │
│  Podman Quadlets (rootless):                                   │
│  • Linkding    • Ntfy           • Papra                        │
│  • Peekaping   • Audiobookshelf • AdGuardHome                  │
│  • Immich      • Karakeep       • SearXNG                      │
│                                                                │
│  Caddy reverse proxy:                                          │
│  • *.internal.crussell.io → internal services                  │
│  • *.crussell.io → public services (via Hetzner)               │
└────────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
          ┌─────────────────┐  ┌─────────────────┐
          │      media      │  │       nas       │
          │ 192.168.20.61   │  │ 192.168.20.31   │
          │ Fedora Server   │  │   TrueNAS       │
          │ Podman stack    │  │ NFS + Beszel    │
          └─────────────────┘  └─────────────────┘
```

## Repository Structure

```text
.
├── AGENTS.md
├── brunch/
│   └── README.md
├── nebula/
│   ├── README.md
│   ├── configs/
│   ├── pki/
│   ├── quadlets/
│   └── scripts/
├── servers/
│   ├── ai/
│   │   └── README.md
│   ├── hub/
│   │   ├── MIGRATION.md
│   │   ├── caddy/
│   │   ├── peekaping/
│   │   │   └── README.md
│   │   └── quadlets/
│   ├── media/
│   │   └── quadlets/
│   ├── nas/
│   │   └── README.md
│   └── gateway/
│       └── README.md
└── .archived/
    ├── nixos/
    └── swarm/
```

## Machine Registry

| Hostname | IP Address | OS | Purpose | Services |
|----------|------------|-----|---------|----------|
| hub | 192.168.20.105 | Fedora Atomic | Main server | Podman Quadlets, Caddy |
| media | 192.168.20.61 | Fedora Server | Media server | Jellyfin, Radarr, Sonarr, Prowlarr, qBittorrent, Jellyseerr |
| nas | 192.168.20.31 | TrueNAS | Network storage | NFS, Beszel agent |
| gateway | 178.156.171.212 | Fedora | Public gateway/VPS | nginx (SSL passthrough → hub via Nebula), Nebula lighthouse + relay |
| think | - | Fedora Atomic | Laptop | ThinkPad T14 |

## SSH Configuration

- **SSH key:** `~/.ssh/id_ed25519`
- **Username:** `crussell`
- **Always use:** `-o IdentitiesOnly=yes` when piping data to avoid agent issues

## Hub Operations (Quick Reference)

Services run as rootless Podman containers via systemd Quadlets.

```bash
# View quadlet source files in repo
ls servers/hub/quadlets/containers/

# Install/update user quadlets from repo
cp servers/hub/quadlets/containers/*.container ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user restart <service>

# Check service status and logs
systemctl --user status <service>
journalctl --user -u <service>
```

Caddy routing config lives at `servers/hub/caddy/Caddyfile`.

```bash
# Validate/reload running Caddy container
sudo podman exec systemd-caddy caddy validate --config /etc/caddy/Caddyfile
sudo podman exec systemd-caddy caddy reload --config /etc/caddy/Caddyfile
```

## Adding or Updating a Hub Service

1. Add or edit a quadlet in `servers/hub/quadlets/containers/`.
2. If externally reachable, add/update route(s) in `servers/hub/caddy/Caddyfile`.
3. Add/update monitoring in `servers/hub/peekaping/monitors.json` and sync via `sync-monitors.sh`.
4. Deploy quadlet to `~/.config/containers/systemd/`, reload daemon, and restart service.
5. Verify with service logs and HTTP checks.

## Archived / Deprecated

Deprecated configs are retained under `.archived/`:

- `.archived/nixos/` - Legacy NixOS configs for decommissioned hosts
- `.archived/swarm/` - Legacy Docker Swarm stack files

# AGENTS.md

This document provides guidance for AI agents operating in this personal infrastructure repository.

## Repository Overview

Personal homelab infrastructure configuration using:
- **Podman Quadlets** on a single server (crussell-srv) for most services
- **Fedora Server** on k1 for media services (to be migrated to Fedora Atomic)
- **TrueNAS** for network storage

## Current Architecture

```
                              Internet
                                  │
                    ┌─────────────▼─────────────┐
                    │      Hetzner VPS          │
                    │  178.156.171.212          │
                    │  (nginx: SSL passthrough) │
                    │  Nebula: 10.10.0.2        │
                    └─────────────┬─────────────┘
                                  │ Nebula VPN
┌─────────────────────────────────▼───────────────────────────────┐
│                        crussell-srv                              │
│                   (192.168.20.105 - This Machine)                │
│                     Nebula split identity:                        │
│                     • 10.10.0.1 local lighthouse                 │
│                     • 10.10.0.6 host/services endpoint           │
│                                                                  │
│  Podman Quadlets (rootless):                                     │
│  • Linkding    • Ntfy           • Papra                          │
│  • Peekaping   • Audiobookshelf • AdGuardHome                    │
│  • Immich      • Karakeep       • SearXNG                        │
│                                                                  │
│  Caddy reverse proxy (system Quadlet):                           │
│  • *.internal.crussell.io → internal services                    │
│  • *.crussell.io → public services (via Hetzner)                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
          ┌─────────────────┐  ┌─────────────────┐
          │       k1        │  │      NAS        │
          │ 192.168.20.61   │  │ 192.168.20.31   │
          │                 │  │   TrueNAS       │
          │ Fedora Server   │  │                 │
          │                 │  │ • NFS shares    │
          │ Podman:         │  │ • Beszel agent  │
          │ • Jellyfin      │  │ • Storage       │
          │ • Jellyseerr    │  │                 │
          │ • Radarr        │  │                 │
          │ • Sonarr        │  │                 │
          │ • Prowlarr      │  │                 │
          │ • qBittorrent   │  │                 │
          └─────────────────┘  └─────────────────┘
```

## Repository Structure

```
/
├── k1/                    # Media server (Fedora → Fedora Atomic TODO)
│   └── README.md          # Services: Jellyfin, Radarr, Sonarr, etc.
├── crussell-srv/          # Main server (this machine)
│   ├── MIGRATION.md       # Swarm → Quadlet migration notes
│   └── quadlets/          # Podman Quadlet definitions
│       └── containers/    # *.container files
├── caddy/                 # Caddy reverse proxy config
├── backups/restic/        # Restic backup configurations
├── truenas/               # TrueNAS Beszel agent config
├── scripts/               # Deployment helper scripts
├── brunch/                # Desktop web app generator
├── bee/                   # Beelink SER7 desktop config
├── vscode/                # VS Code settings
├── archived/              # Deprecated configs (reference only)
│   ├── nixos/             # Old NixOS configs (k2, k3, k4)
│   └── swarm/             # Old Docker Swarm stacks
└── TODO.md                # Outstanding tasks
```

## Machine Registry

| Hostname | IP Address | OS | Purpose | Services |
|----------|------------|-----|---------|----------|
| **crussell-srv** | 192.168.20.105 | Fedora Atomic | Main server | Podman Quadlets, Caddy |
| k1 | 192.168.20.61 | Fedora Server | Media server | Jellyfin, Radarr, Sonarr, Prowlarr, qBittorrent, Jellyseerr |
| nas | 192.168.20.31 | TrueNAS | Network storage | NFS, Beszel agent |
| hetzner | 178.156.171.212 | Fedora | Public gateway/VPS | nginx (SSL passthrough → crussell-srv via Nebula), Nebula lighthouse + relay |
| bee | 192.168.20.105 | Bluefin | Personal desktop | Beelink SER7 (same machine as crussell-srv) |
| think | - | Bluefin | Laptop | ThinkPad T14 |

**Decommissioned:** k2, k3, k4 (NixOS nodes - archived)

## SSH Configuration

- **SSH key:** `~/.ssh/id_ed25519`
- **Username:** `crussell`
- **Always use:** `-o IdentitiesOnly=yes` when piping data to avoid agent issues

```bash
# Connect to machines
ssh k1                    # crussell@192.168.20.61
ssh nas                   # crussell@192.168.20.31
```

## Podman Quadlets (crussell-srv)

Services run as rootless Podman containers via systemd Quadlets.

### Active Quadlets

| Service | Container File | Port | Purpose |
|---------|----------------|------|---------|
| Linkding | `linkding.container` | 9090 | Bookmarks |
| Ntfy | `ntfy.container` | 80 | Notifications |
| Peekaping | `peekaping.container` | 30087 | Uptime monitoring |
| Audiobookshelf | `audiobookshelf.container` | 13378 | Audiobooks/podcasts |
| AdGuardHome | `adguardhome.container` | 3000/53 | DNS filtering |
| Papra | `papra.container` | 1221 | Document management |
| Immich | `immich-*.container` | 2283 | Photo management |
| Karakeep | `karakeep-*.container` | 3000 | Bookmarking |
| SearXNG | `searxng-*.container` | 8080 | Search aggregator |

### Quadlet Management

```bash
# List running containers
podman ps

# View quadlet files
ls ~/.config/containers/systemd/

# Apply quadlet changes
cp crussell-srv/quadlets/containers/*.container ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user restart <service>

# View logs
journalctl --user -u <service>

# Service status
systemctl --user status <service>
```

### Adding New Services

1. Create `service-name.container` in `crussell-srv/quadlets/containers/`
2. Copy to `~/.config/containers/systemd/`
3. Run `systemctl --user daemon-reload`
4. Enable and start: `systemctl --user enable --now service-name`

## Caddy Reverse Proxy

Caddy handles all reverse proxy routing on crussell-srv.

**Config:** `crussell-srv/caddy/Caddyfile`
**Running as:** System-level Podman Quadlet (`/etc/containers/systemd/caddy.container`)
**Network:** Host mode (required to access 127.0.0.1 backends)

**Routes:**
- `*.internal.crussell.io` → Internal services (linkding, immich, etc.)
- `*.crussell.io` → Public services (jellyfin, photos, homeassistant, etc.)

**Public Traffic Flow:**
```
Internet → Hetzner (nginx SSL passthrough) → Nebula 10.10.0.6 → crussell-srv Caddy
```

**Manage Caddy:**
```bash
# Reload config
sudo podman exec systemd-caddy caddy reload --config /etc/caddy/Caddyfile

# Validate config
sudo podman exec systemd-caddy caddy validate --config /etc/caddy/Caddyfile

# View logs
journalctl -u caddy -f
```

**Image:** Custom build with Route53 DNS challenge support (`localhost/caddy-route53:latest`)

## Nebula

Nebula provides the mesh VPN for secure connectivity between all nodes.

**Key facts:**
- Local lighthouse on `crussell-srv`: `10.10.0.1` (UDP 4243, discovery-only)
- crussell-srv host identity: `10.10.0.6` (Caddy/backend endpoint)
- Hetzner lighthouse + relay: `10.10.0.2` (public, UDP 4242)
- Internal DNS (`*.internal.crussell.io`) points to `10.10.0.6`

**Full details:** See `nebula/README.md` for topology, config files, cert management, and troubleshooting.

## Restic Backups

**Repository:** `/mnt/backups/restic` (NFS from NAS)
**Schedule:** Daily at 3:00 AM
**Retention:** 90 days

**Services backed up from crussell-srv:**
- Linkding, Ntfy, Papra, Audiobookshelf, AdGuardHome
- Immich (database + uploads)
- Karakeep (database + data)
- SearXNG

**Manual backup:**
```bash
sudo restic-backup
```

**Check backups:**
```bash
sudo restic snapshots --repo /mnt/backups/restic --password-file /etc/restic-password
```

## k1 Media Server

Media server running on Fedora Server. **TODO: Migrate to Fedora Atomic.**

**Services (Podman):**
- Jellyfin (port 8096) - Media streaming
- Jellyseerr (port 5055) - Request management
- Radarr (port 7878) - Movie automation
- Sonarr (port 8989) - TV automation
- Prowlarr (port 9696) - Indexer aggregation
- qBittorrent (port 8080) - Download client

**Access:**
```bash
ssh -i ~/.ssh/id_ed25519 crussell@192.168.20.61
```

**TODO:**
- Capture configs into this repo
- Create Quadlet definitions
- Migrate to Fedora Atomic

## TrueNAS (nas)

Network storage at 192.168.20.31.

**Provides:**
- NFS shares for backups and data
- Beszel monitoring agent

**Config location:** `truenas/docker-compose.yml` (Beszel agent)

## Brunch (Desktop Web Apps)

System for creating desktop apps from web services.

**Location:** `brunch/`

## Adding New Services

1. **Create Quadlet** in `crussell-srv/quadlets/containers/`
2. **Add Caddy route** if external access needed
3. **Add DNS record** in Route53 (manual)
4. **Add to backups** in `backups/restic/`
5. **Add to Peekaping** for monitoring

## Archived / Deprecated

All deprecated configs are in `archived/` for reference:

- **archived/nixos/** — NixOS configs for k2, k3, k4 (decommissioned)
- **archived/swarm/** — Docker Swarm stack files (migrated to Podman Quadlets)

## Troubleshooting

**Podman container won't start:**
```bash
podman logs <container-name>
journalctl --user -u <service>
```

**NFS mount issues:**
```bash
mount | grep nfs
sudo mount -a
```

**SSH "Too many authentication failures":**
```bash
ssh -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 user@host
```

# AGENTS.md

This document provides guidance for AI agents operating in this personal infrastructure repository.

## Repository Overview

Personal homelab infrastructure configuration using:
- **Podman Quadlets** on a single server (crussell-srv) for most services
- **Fedora Server** on k1 for media services (to be migrated to Fedora Atomic)
- **TrueNAS** for network storage

## Current Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        crussell-srv                              │
│                   (192.168.20.105 - This Machine)                │
│                                                                  │
│  Podman Quadlets (rootless):                                     │
│  • Linkding    • Ntfy           • Papra                          │
│  • Peekaping   • Audiobookshelf • AdGuardHome                    │
│  • Immich      • Karakeep       • SearXNG                        │
│                                                                  │
│  Also runs: Caddy reverse proxy                                  │
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

Caddy routes traffic to internal services.

**Config:** `caddy/Caddyfile`
**Routes:**
- `*.internal.crussell.io` → Internal services
- `*.crussell.io` → Public services

**Running on:** This machine (crussell-srv)

**Update Caddy:**
```bash
# If there's an update script
./caddy/update_caddy.sh

# Or manually
sudo systemctl restart caddy
```

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

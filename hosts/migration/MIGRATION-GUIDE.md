# Migration Guide: k1–k4 → bee + bees

**Goal**: Move all services and data off k1, k2, k3, k4 onto `bee` and `bees`, then validate nothing is left behind.

## Progress Tracker

### Pre-Migration
- [x] bees installed with NixOS (2026-05-05)
- [x] Nebula connected at 10.10.0.5
- [x] SSH verified: `ssh -o IdentitiesOnly=yes crussell@192.168.20.41`

### Phase 1: Migrate k3 → bees (Media stack) — IN PROGRESS
- [x] Media services config deployed to bees (`hosts/bees/media-services.nix`)
- [x] All services installed and running on bees
- [x] k3 services stopped
- [x] Data transferred (rsync over direct Ethernet k3→bees)
- [x] Database corruption fixed (re-rsync'd with k3 stopped)
- [x] All 6 services healthy on bees (Jellyfin, Sonarr, Radarr, Prowlarr, Jellyseerr, qBittorrent)
- [x] **USER VALIDATION NEEDED** — browse each service, verify data integrity
- [x] Cut traffic over (update Caddy routes to point to bees)
- [x] Final validation

### Phase 2: Migrate k4 → bees (Immich) — IN PROGRESS
- [x] Immich config added to bees (`hosts/bees/immich.nix`)
- [x] PostgreSQL data transferred (pg_dump/pg_restore PG16→PG17)
- [x] Redis data transferred
- [x] Immich services running on bees
- [x] Caddy route for `photos.crussell.io` updated to bees (192.168.20.41)
- [x] **USER VALIDATION NEEDED** — verify Immich on bees
- [x] Cut traffic over (Caddy route updated, needs validation)
- [x] Final validation
### Phase 3: Migrate k2 → bees (Ingress + shared services) — IN PROGRESS
- [x] All k2 service configs copied to bees (ntfy, searxng, datenight, caddy, hub-services)
- [x] SearXNG port changed to 8888 (conflict with qBittorrent on 8080)
- [x] Caddy routes updated to point to localhost on bees
- [x] caddy-route53 container image transferred from k2
- [x] Caddy TLS certs/ACME state transferred
- [x] aws.env Route53 credentials transferred
- [x] All service data transferred (ntfy, datenight, linkding, papra, open-webui)
- [x] All services running on bees (caddy, ntfy, searxng, datenight, linkding, papra, open-webui, immich)
- [x] k2 services stopped
- [x] **USER VALIDATION NEEDED** — verify all services through Caddy on bees
- [x] Update gateway Hetzner to point to bees (or update Nebula identity)
- [x] Final validation
### Phase 4: Migrate Nebula lighthouse → bee — DONE
- [x] Lighthouse config added to bee configuration.nix
- [x] Lighthouse certs transferred from k2 to bee
- [x] nebula-client.nix staticHostMap updated to point to bee (192.168.20.105:4243)
- [x] Deployed bee, bees with updated config
- [x] k2 lighthouse stopped
- [x] Nebula connectivity verified (ping lighthouse + gateway)
- [x] Public services verified through gateway
### Phase 5: Migrate k1 → bee (Gloo dev stack) — NOT STARTED
### Phase 6: Repo cleanup — NOT STARTED
### Phase 7: Final validation sweep — NOT STARTED
### Phase 8: Smoke test everything — NOT STARTED

## Lessons Learned (2026-05-05)

### bees hardware quirks
- **NIC**: Intel E610 10GbE (PCI ID 8086:57b0) uses `ixgbe` driver, NOT `ice`
- **Kernel**: Default NixOS 6.12 kernel's `ixgbe` does NOT recognize the E610. Must use `linuxPackages_latest` (7.0.x)
- **Firmware**: Must set `hardware.enableAllFirmware = true` and `nixpkgs.config.allowUnfree = true`
- **ixgbe in kernelModules**: Must be in `boot.initrd.kernelModules` (not just `availableKernelModules`) to ensure it loads during boot
- **Network matching**: Match by MAC address (`78:55:36:02:ce:bf`) not interface name — more reliable across OS changes
- **RAM**: Only ~32 GB visible to OS (rest shared with integrated Radeon 8060S GPU)

### nixos-anywhere on bees
- The install script uses `crussell@` for bees (passwordless sudo). Must use `nix run github:nix-community/nixos-anywhere -- --flake .#bees root@IP` from live USB since root has password auth
- Boot the NixOS live USB, set root password, start sshd, then run nixos-anywhere from thinkpad

### Data transfer
- **Always stop services on source BEFORE transferring data**. We corrupted Radarr/Prowlarr SQLite DBs by transferring while services were still running on k3
- Use `sudo rsync -avz --progress --rsync-path="sudo rsync"` for root-level files between servers (SSH as crussell with sudo on both ends)
- Set up root SSH key auth between servers for direct transfer (avoids WiFi bottleneck through thinkpad)
- The tar-pipe-through-thinkpad approach (`ssh k3 "tar cf - ..." | ssh bees "tar xf -"`) works but times out for large transfers (>8GB). Prefer direct rsync between servers.

### Nebula on bees
- Nebula cert files need `chown root:nebula-homelab` and `chmod 0440` — the service runs as nebula-homelab user, not root
- Deploy certs: decrypt with `age -d -i ~/.ssh/id_ed25519 -o /tmp/bees-host.key nebula/pki/bees.key.age`, then scp and sudo mv

**Target architecture**:

```
                              Internet
                                  │
                                  ▼
                ┌──────────────────────────────────┐
                │ gateway / Hetzner VPS             │
                │ nginx stream → bees (new target)  │
                │ Nebula lighthouse+relay 10.10.0.2 │
                └───────────────┬──────────────────┘
                                │ Nebula
                ┌───────────────┴──────────────┐
                ▼                              ▼
  ┌──────────────────────────┐   ┌──────────────────────────┐
  │ bees — production server │   │ bee — dev + Nebula LH    │
  │ 192.168.20.41            │   │ 192.168.20.105           │
  │ Nebula 10.10.0.5         │   │ Nebula 10.10.0.12        │
  │                          │   │                          │
  │ AMD Ryzen AI MAX+ 395    │   │ AMD Ryzen 7 7840HS       │
  │ 16C/32T, 128 GB RAM     │   │ 8C/16T, 28 GB RAM        │
  │ 2 TB NVMe, dual 10GbE   │   │ 1 TB NVMe, 1 GbE         │
  │                          │   │                          │
  │ SERVICES FROM:           │   │ SERVICES FROM:           │
  │  k2 → Caddy, ntfy,      │   │  k2 → Nebula lighthouse  │
  │       SearXNG, datenight,│   │  k1 → Gloo dev stack     │
  │       linkding, papra,   │   │                          │
  │       open-webui         │   │                          │
  │  k3 → Jellyfin, Sonarr, │   │                          │
  │       Radarr, Prowlarr,  │   │                          │
  │       qBittorrent,       │   │                          │
  │       Jellyseerr         │   │                          │
  │  k4 → Immich             │   │                          │
  └──────────┬───────────────┘   └──────────┬───────────────┘
             │ NFS (prefer 10GbE)            │ NFS
             ▼                                ▼
    ┌─────────────────┐            ┌─────────────────┐
    │ nas / TrueNAS   │            │ nas / TrueNAS   │
    │ 192.168.20.31   │            │ 192.168.20.31   │
    └─────────────────┘            └─────────────────┘
```

---

## Pre-Migration: Prerequisites

### 1. Get bees online on Nebula

bees (192.168.20.41, 10.10.0.5) is currently running Fedora 43 and is unreachable via Nebula. Before anything else:

- [ ] Confirm bees is powered on and accessible at `192.168.20.41` (LAN)
- [ ] Decide: install NixOS fresh on bees, or configure services on Fedora?
  - **Recommendation**: Fresh NixOS install via `nixos-anywhere`, consistent with all other hosts
- [ ] Create `hosts/bees/configuration.nix` in the repo
- [ ] Install bees with `nix run .#install -- bees 192.168.20.41` (WARNING: destructive)
- [ ] Verify Nebula connects: `ping 10.10.0.5` from think/bee
- [ ] Verify SSH: `ssh -o IdentitiesOnly=yes root@10.10.0.5`

### 2. Update gateway routing

After migration, the Hetzner gateway needs to forward to bees instead of k2:

- [ ] Update nginx stream proxy on `178.156.171.212` to point to `10.10.0.5:80` and `10.10.0.5:443` (instead of `10.10.0.6`)
- [ ] Or: keep pointing to k2's Nebula IP and use Nebula routing (simpler, no gateway change needed if bees takes over k2's Nebula identity)

### 3. Decide on Nebula identity strategy

Two options:

**Option A (simpler, recommended)**: bees takes over k2's Nebula IP `10.10.0.6`. All existing clients and the gateway already point to `10.10.0.6` for Caddy. Just swap the certs.

**Option B**: bees keeps `10.10.0.5`, update gateway + all client configs to point to new IP.

> This guide assumes **Option A** for minimal disruption. If you choose Option B, update all IPs in the checklist steps.

---

## Phase 1: Migrate k3 → bees (Media stack)

**Why first**: Media services are the heaviest users. Getting them onto bees proves the machine can handle the load. k3 services are self-contained with NFS storage.

### Services and data to transfer

| Service | Data location | Size | Config source |
|---------|--------------|------|---------------|
| Jellyfin | `/var/lib/jellyfin/` | 8.3 GB | `hosts/k3/media-services.nix` |
| Sonarr | `/var/lib/sonarr/` | 124 MB | `hosts/k3/media-services.nix` |
| Radarr | `/var/lib/radarr/` | 68 MB | `hosts/k3/media-services.nix` |
| Prowlarr | `/var/lib/prowlarr/` | 111 MB | `hosts/k3/media-services.nix` |
| Jellyseerr | `/var/lib/jellyseerr/` | 7.5 MB | `hosts/k3/media-services.nix` |
| qBittorrent | `/var/lib/qBittorrent/` | 3.2 GB | `hosts/k3/media-services.nix` |

**Note**: qBittorrent downloads go directly to `/mnt/media/Downloads` on NFS. No local torrent data. The BT_backup directory contains active torrent state (`.torrent` + `.fastresume` files — 7 torrents currently).

### Steps

#### 1A. Prepare bees NixOS config

- [ ] Create `hosts/bees/configuration.nix` with:
  - `imports = [ ../../modules/base-server.nix ./disk-config.nix ../../modules/nebula-client.nix ];`
  - `networking.hostName = "bees";`
  - NFS mounts: `/mnt/media`, `/mnt/photos`, `/mnt/backups`
  - `services.nebula.networks.homelab.enable = true;`
  - Firewall ports as needed
- [ ] Create `hosts/bees/disk-config.nix` for the 2 TB NVMe
- [ ] Build and validate: `nix eval .#nixosConfigurations.bees.config.networking.hostName --raw`
- [ ] Deploy: `nix run .#deploy -- bees`

#### 1B. Add media services to bees config

- [ ] Copy `hosts/k3/media-services.nix` → `hosts/bees/media-services.nix`
- [ ] Import it from `hosts/bees/configuration.nix`
- [ ] Adjust any paths if needed (should be identical — same NFS mounts)
- [ ] Deploy bees to create the service definitions
- [ ] Stop all media services on k3:
  ```bash
  ssh root@10.10.0.8 'systemctl stop jellyfin sonarr radarr prowlarr jellyseerr qbittorrent'
  ```

#### 1C. Transfer service data

```bash
# From bees (or via SSH proxy), rsync each service's data directory:
# Run these as root on bees, pulling from k3 via Nebula

SERVICES="jellyfin sonarr radarr prowlarr jellyseerr"
for svc in $SERVICES; do
  rsync -avz --progress root@10.10.0.8:/var/lib/$svc/ /var/lib/$svc/
done

# qBittorrent (note capital B)
rsync -avz --progress root@10.10.0.8:/var/lib/qBittorrent/ /var/lib/qBittorrent/
```

- [ ] Verify sizes match: `du -sh /var/lib/{jellyfin,sonarr,radarr,prowlarr,jellyseerr,qBittorrent}` on both machines
- [ ] Verify file counts: `find /var/lib/$svc -type f | wc -l` on both machines

#### 1D. Fix ownership and start services

```bash
# Fix ownership for each service user
for svc in jellyfin sonarr radarr prowlarr jellyseerr; do
  chown -R $svc:$svc /var/lib/$svc
done
chown -R qbittorrent:media /var/lib/qBittorrent
```

- [ ] Start services on bees:
  ```bash
  systemctl start jellyfin sonarr radarr prowlarr jellyseerr qbittorrent
  ```
- [ ] Check all services are running: `systemctl status jellyfin sonarr radarr prowlarr jellyseerr qbittorrent`
- [ ] Verify Jellyfin web UI: `curl -I http://localhost:8096`
- [ ] Verify qBittorrent web UI: `curl -I http://localhost:8080`
- [ ] Verify qBittorrent shows all 7 torrents with correct save paths

#### 1E. Validate media stack migration

- [ ] Jellyfin: browse library, play a video, verify transcoding works
- [ ] Sonarr: check series list, verify connection to Prowlarr and qBittorrent
- [ ] Radarr: check movie list, verify connections
- [ ] Prowlarr: check indexers
- [ ] Jellyseerr: verify it connects to Jellyfin
- [ ] qBittorrent: verify all torrents seeding, no errors, download path correct (`/mnt/media/Downloads`)

#### 1F. Validation checklist — k3 media data fully migrated

- [ ] Service data sizes match between k3 and bees
- [ ] All services healthy on bees
- [ ] All services stopped on k3
- [ ] k3 `/mnt/data` (local HDD) contents reviewed — only legacy Longhorn data (3.9 GB, can be discarded)
- [ ] No unique data remains on k3

---

## Phase 2: Migrate k4 → bees (Immich)

### Services and data to transfer

| Service | Data location | Size |
|---------|--------------|------|
| Immich server | `/var/lib/immich/` | 4 KB (config only) |
| Immich ML | (no persistent data) | — |
| PostgreSQL | `/var/lib/postgresql/` | 395 MB |
| Redis | `/var/lib/redis-immich/` | 16 KB |
| Photos | `/mnt/photos` (NFS, stays on NAS) | — |

### Steps

#### 2A. Add Immich to bees config

- [x] Copy Immich config from `hosts/k4/configuration.nix` into `hosts/bees/immich.nix`
- [x] Import it from `hosts/bees/configuration.nix`
- [x] Create the `nas-photos` group (GID 1000) and user config
- [x] Deploy bees

#### 2B. Stop and transfer

```bash
# Stop on k4
ssh root@10.10.0.9 'systemctl stop immich-server immich-machine-learning redis-immich'

# Transfer postgres data (most important — has all metadata, albums, faces)
rsync -avz --progress root@10.10.0.9:/var/lib/postgresql/ /var/lib/postgresql/

# Transfer redis (session cache, less critical)
rsync -avz --progress root@10.10.0.9:/var/lib/redis-immich/ /var/lib/redis-immich/

# Transfer immich config
rsync -avz --progress root@10.10.0.9:/var/lib/immich/ /var/lib/immich/
```

- [x] Verify sizes match
- [x] Fix ownership: `chown -R postgres:postgres /var/lib/postgresql`
- [x] Fix ownership: `chown -R redis-immich:redis-immich /var/lib/redis-immich`
- [x] Fix ownership: `chown -R immich:immich /var/lib/immich`

#### 2C. Start and validate

- [x] Start services: `systemctl start postgresql redis-immich immich-server immich-machine-learning`
- [x] Verify web UI: `curl -I http://localhost:2283`
- [x] Login and verify: photo count matches, albums present, face tags intact
- [x] Test upload: upload one photo, verify it appears and ML processes it

#### 2D. Validation checklist — k4 data fully migrated

- [x] PostgreSQL dump matches (row counts on key tables)
- [x] All Immich services healthy on bees
- [x] All Immich services stopped on k4
- [x] No unique data on k4 (photos are on NFS, not local disk — only 6.3 GB on NVMe root)

---

## Phase 3: Migrate k2 → bee (Ingress + shared services)

**This is the critical phase** — bee becomes the main ingress point.

### Services and data to transfer

| Service | Data location | Size | Notes |
|---------|--------------|------|-------|
| Caddy (Podman) | `/var/lib/containers/storage/volumes/caddy_data/` | 108 KB | TLS certs + ACME state |
| Caddy (Podman) | `/var/lib/containers/storage/volumes/caddy_config/` | 20 KB | Auto-generated |
| Caddy config | `/etc/caddy/` | 40 KB | Managed by NixOS — see below |
| Caddy Route53 creds | `/etc/caddy/aws.env` | 145 B | **SENSITIVE** — migrate to agenix |
| ntfy | `/var/lib/ntfy-sh/` | 144 KB | user.db + cache.db + attachments |
| SearXNG | (no persistent data) | — | Config is Nix-managed |
| datenight | `/var/lib/datenight/` | 8 KB | Minimal state |
| linkding | `/srv/linkding/` | 4.4 MB | Bookmarks |
| papra | `/srv/papra/` | 14 MB | Documents |
| open-webui | `/srv/open-webui/` | 1.1 GB | Chat history, models |

### Steps

#### 3A. Transfer Caddy configuration

Caddy config is fully managed by NixOS (`hosts/k2/caddy.nix` + `hosts/k2/caddy/`). The approach:

- [ ] Copy `hosts/k2/caddy.nix` → `hosts/bee/caddy.nix`
- [ ] Copy `hosts/k2/caddy/` → `hosts/bee/caddy/`
- [ ] Copy `hosts/k2/hub-services.nix` → `hosts/bee/hub-services.nix` (linkding, papra, open-webui containers)
- [ ] Copy `hosts/k2/*.container` files → `hosts/bee/`
- [ ] Copy `hosts/k2/ntfy.nix` → `hosts/bee/ntfy.nix`
- [ ] Copy `hosts/k2/searxng.nix` → `hosts/bee/searxng.nix`
- [ ] Copy `hosts/k2/datenight.nix` → `hosts/bee/datenight.nix`
- [ ] Import all from `hosts/bee/configuration.nix`
- [ ] Update internal route targets in Caddy routes:
  - `hosts/bee/caddy/routes/internal/gloo.caddy` → point to bee (10.10.0.12 or bee's LAN IP)
  - `hosts/bee/caddy/routes/internal/media.caddy` → point to `localhost` (now on bee)
  - All other internal routes → `localhost` where the service now runs on bee
- [ ] **Migrate `aws.env` to agenix** — create `secrets/caddy-route53.env.age`, reference in bee config
- [ ] Update `hosts/k2/caddy/routes/internal/media.caddy` — media services now on bee itself
- [ ] Deploy bee

#### 3B. Stop k2 services, transfer data

```bash
# Stop everything on k2
ssh root@10.10.0.6 '
  systemctl stop caddy ntfy-sh searx datenight linkding papra open-webui
'

# Transfer service data to bee
# (run from bee, or from thinkpad with appropriate jump hosts)

# ntfy (user database, cached messages, attachments)
rsync -avz --progress root@10.10.0.6:/var/lib/ntfy-sh/ /var/lib/ntfy-sh/

# linkding (bookmarks)
rsync -avz --progress root@10.10.0.6:/srv/linkding/ /srv/linkding/

# papra (documents)
rsync -avz --progress root@10.10.0.6:/srv/papra/ /srv/papra/

# open-webui (chat history, model configs — biggest)
rsync -avz --progress root@10.10.0.6:/srv/open-webui/ /srv/open-webui/

# datenight (minimal state)
rsync -avz --progress root@10.10.0.6:/var/lib/datenight/ /var/lib/datenight/

# Caddy TLS certs and ACME state
rsync -avz --progress root@10.10.0.6:/var/lib/containers/storage/volumes/caddy_data/ /var/lib/containers/storage/volumes/caddy_data/
rsync -avz --progress root@10.10.0.6:/var/lib/containers/storage/volumes/caddy_config/ /var/lib/containers/storage/volumes/caddy_config/
```

- [ ] Verify all sizes match
- [ ] Fix ownership for each service

#### 3C. Start services and validate ingress

- [ ] Start all services on bee
- [ ] Validate Caddy internally: `podman exec systemd-caddy caddy validate --config /etc/caddy/Caddyfile`
- [ ] Reload Caddy: `podman exec systemd-caddy caddy reload --config /etc/caddy/Caddyfile`

If using **Option A** (bee takes k2's Nebula IP 10.10.0.6):
- [ ] Update bee' Nebula config to use k2's certs (`/etc/nebula/host.crt`, `host.key`)
- [ ] Update k2's Nebula config to use a different IP or disable it
- [ ] The gateway (`178.156.171.212`) needs no changes — still forwards to 10.10.0.6

If using **Option B** (bee keeps 10.10.0.5):
- [ ] Update gateway nginx to forward to 10.10.0.5 instead of 10.10.0.6
- [ ] Update any hardcoded Nebula IPs in client configs

#### 3D. Validate external access

- [ ] `curl -I https://homeassistant.crussell.io` → should reach HA
- [ ] `curl -I https://jellyfin.crussell.io` → should reach bee/Jellyfin
- [ ] `curl -I https://photos.crussell.io` → should reach bee/Immich
- [ ] `curl -I https://datenight.crussell.io` → should reach bee/datenight
- [ ] Verify internal routes (from LAN or Nebula):
  - `https://ntfy.internal.crussell.io` → bee/ntfy
  - `https://search.internal.crussell.io` → bee/SearXNG
  - `https://linkding.internal.crussell.io` → bee/linkding
  - `https://papra.internal.crussell.io` → bee/papra
  - `https://open-webui.internal.crussell.io` → bee/open-webui

#### 3E. Validation checklist — k2 data fully migrated

- [ ] ntfy: verify existing subscriptions still push notifications
- [ ] linkding: verify all bookmarks present, login works
- [ ] papra: verify documents accessible
- [ ] open-webui: verify chat history, model configs
- [ ] SearXNG: verify search works (no data to transfer — config only)
- [ ] datenight: verify app loads
- [ ] Caddy: TLS certs valid for all public domains
- [ ] Caddy: internal routes resolve correctly
- [ ] All k2 services stopped
- [ ] k2 `/var/lib/containers/` total size matches bee
- [ ] `aws.env` Route53 creds securely stored (no longer plaintext on disk, or at minimum present on bee)
- [ ] No unique data remains on k2

---

## Phase 4: Migrate Nebula lighthouse → bee

k2 currently runs the local Nebula lighthouse (10.10.0.1 on UDP 4243). Move it to bee.

- [ ] Copy lighthouse config from `hosts/k2/configuration.nix` (the `services.nebula.networks.lighthouse` block) into `hosts/bee/configuration.nix`
- [ ] Copy lighthouse certs from k2 (`/etc/nebula-lh/`) to bee
- [ ] Update all client Nebula configs to point lighthouse at bee's LAN IP (or 127.0.0.1 if on same machine)
- [ ] Deploy bee, verify lighthouse: `systemctl status nebula@lighthouse`
- [ ] Test from thinkpad: disconnect and reconnect Nebula, verify it finds the lighthouse

---

## Phase 5: Migrate k1 → bee (Gloo dev stack)

### Services and data to transfer

| Service | Data location | Size |
|---------|--------------|------|
| Gloo source code | `/home/crussell/Gloo/` | 2.0 GB |
| Gloo user units | `/home/crussell/.config/systemd/user/` | Generated by NixOS |
| Gloo env files | `/etc/gloo/envs/*.env` | Managed by NixOS |
| Gloo compose | `/etc/gloo/compose.yaml` | Managed by NixOS |
| Podman volumes (postgres, rustfs, pgadmin) | Podman-managed | Check with `podman volume ls` |
| Agenix key | `/home/crussell/.config/age/key.txt` | Needed for secret decryption |
| pnpm store | `/home/crussell/.local/share/pnpm/` | Shared Node tooling |

### Steps

#### 5A. Add Gloo to bee config

- [x] Copy `hosts/k1/gloo.nix` → `hosts/bee/gloo.nix`
- [x] Copy `hosts/k1/gloo/` directory → `hosts/bee/gloo/`
- [x] Copy `hosts/k1/buildspace.nix` → `hosts/bee/buildspace.nix` (disabled, same as k1)
- [x] Copy agenix secret reference: `secrets/gloo-secrets.env.age`
- [x] Import from `hosts/bee/configuration.nix`
- [x] Deploy bee

#### 5B. Transfer Gloo data

```bash
# Stop Gloo on k1
ssh -o IdentitiesOnly=yes -J root@10.10.0.6 root@192.168.20.61 '
  export XDG_RUNTIME_DIR=/run/user/$(id -u crussell)
  sudo -u crussell XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR systemctl --user stop gloo-all.target
'

# Transfer Gloo source code
rsync -avz --progress -J root@10.10.0.6 root@192.168.20.61:/home/crussell/Gloo/ /home/crussell/Gloo/

# Transfer Podman volumes from k1
# First, list them on k1:
#   podman volume ls
# Then for each volume:
#   podman volume inspect <name> --format "{{.Mountpoint}}"
#   rsync -avz <source> <destination on bee>
```

- [x] Verify source code matches
- [x] Verify Podman volumes transferred (postgres data, rustfs data, pgadmin data)
- [x] Copy agenix key: transfer `/home/crussell/.config/age/key.txt` to bee

#### 5C. Start Gloo on bee

- [x] Start: `sudo -u crussell XDG_RUNTIME_DIR=/run/user/$(id -u crussell) systemctl --user start gloo-all.target`
- [x] Verify infra: `podman ps` shows postgres, rustfs, pgadmin running
- [x] Verify app services: check each dev server responds on its port
- [x] Update Caddy route on bee: `hosts/bee/caddy/routes/internal/gloo.caddy` → point to bee's LAN IP

#### 5D. Validation checklist — k1 data fully migrated

- [x] All 6 Gloo dev services running on bee
- [x] Podman infra services running (postgres, rustfs, pgadmin)
- [x] Database data intact (check a few records)
- [x] S3 buckets intact (check rustfs console)
- [x] Caddy routes for `*.internal.crussell.io` Gloo services point to bee
- [x] All k1 services stopped
- [x] No unique data on k1 NVMe (only 8.4 GB used, mostly Gloo source which is git-managed)
- [x] k1 `/mnt/data` (1.8 TB HDD) — only 2.1 MB used, empty

---

## Phase 6: Update repo and Nebula PKI

### Repo cleanup

- [ ] Update `AGENTS.md` with new architecture diagram and machine registry
- [ ] Remove or archive `hosts/k1/`, `hosts/k2/`, `hosts/k3/`, `hosts/k4/` configs (keep for reference initially)
- [ ] Update `flake.nix` to remove k1-k4 from nixosConfigurations (or mark as disabled)
- [ ] Update `modules/nebula-hosts.nix` if Nebula IPs change
- [ ] Remove k2's lighthouse config from its host config
- [ ] Update `hosts/homeassistant/` docs if any references to k2/k3 IPs

### Nebula PKI updates

- [ ] If bee takes k2's identity (10.10.0.6): update cert files in `nebula/pki/`
- [ ] Revoke old k1-k4 certs if desired (or just let them expire unused)
- [ ] Update `modules/nebula-client.nix` with new lighthouse address if it moved to bee

### Gateway update

- [ ] If using Option A: no gateway change needed (10.10.0.6 still the target)
- [ ] If using Option B: update `178.156.171.212` nginx config to point to new Nebula IP
- [ ] Test: `curl -I https://jellyfin.crussell.io` from outside LAN

---

## Phase 7: Final validation sweep

Run through this checklist for each retired machine before powering them off for good.

### k1 (192.168.20.61 / 10.10.0.4)

- [ ] All services stopped and disabled: `systemctl list-units --type=service --state=running` shows only base OS services
- [ ] No user services: `sudo -u crussell XDG_RUNTIME_DIR=/run/user/$(id -u crussell) systemctl --user list-units --state=running`
- [ ] Data inventory:
  ```
  /home/crussell/Gloo/          → 2.0 GB (migrated to bee, or git-managed)
  /home/crussell/.config/age/   → age key (migrated to bee)
  /etc/gloo/                    → Nix-managed, no unique data
  /mnt/data/                    → 2.1 MB used, empty
  /mnt/backups/                 → NFS, not local
  ```
- [ ] Confirm: no data on k1 that doesn't exist elsewhere
- [ ] Power off: `ssh root@192.168.20.61 'poweroff'`
- [ ] Physically unplug and label as spare/retired

### k2 (192.168.20.62 / 10.10.0.6)

- [ ] All services stopped: `systemctl list-units --type=service --state=running`
- [ ] All Podman containers stopped: `podman ps -a`
- [ ] Data inventory:
  ```
  /var/lib/containers/          → 12 GB (Caddy + hub services data, migrated to bee)
  /var/lib/ntfy-sh/             → 144 KB (migrated to bee)
  /srv/linkding/                → 4.4 MB (migrated to bee)
  /srv/papra/                   → 14 MB (migrated to bee)
  /srv/open-webui/              → 1.1 GB (migrated to bee)
  /var/lib/datenight/           → 8 KB (migrated to bee)
  /etc/caddy/aws.env            → 145 B (SENSITIVE, migrated to bee — then delete from k2)
  /etc/nebula-lh/               → Lighthouse certs (migrated to bee)
  /mnt/backups/                 → NFS, not local
  ```
- [ ] Confirm: no data on k2 that doesn't exist elsewhere
- [ ] **Delete** `aws.env` from k2 disk after confirming it works on bee
- [ ] Power off: `ssh root@192.168.20.62 'poweroff'`
- [ ] Physically unplug and label as spare/retired

### k3 (192.168.20.63 / 10.10.0.8)

- [ ] All services stopped: `systemctl list-units --type=service --state=running`
- [ ] Data inventory:
  ```
  /var/lib/jellyfin/            → 8.3 GB (migrated to bees)
  /var/lib/sonarr/              → 124 MB (migrated to bees)
  /var/lib/radarr/              → 68 MB (migrated to bees)
  /var/lib/prowlarr/            → 111 MB (migrated to bees)
  /var/lib/jellyseerr/          → 7.5 MB (migrated to bees)
  /var/lib/qBittorrent/         → 3.2 GB (migrated to bees)
  /mnt/data/                    → 3.9 GB (legacy Longhorn data — can be discarded)
  /mnt/media/                   → NFS, not local
  /mnt/backups/                 → NFS, not local
  ```
- [ ] Confirm: no data on k3 that doesn't exist elsewhere
- [ ] `/mnt/data` reviewed and contents confirmed discardable
- [ ] Power off: `ssh root@192.168.20.63 'poweroff'`
- [ ] Physically unplug and label as spare/retired

### k4 (192.168.20.64 / 10.10.0.9)

- [ ] All services stopped: `systemctl list-units --type=service --state=running`
- [ ] Data inventory:
  ```
  /var/lib/postgresql/          → 395 MB (migrated to bees)
  /var/lib/redis-immich/        → 16 KB (migrated to bees)
  /var/lib/immich/              → 4 KB (migrated to bees)
  /mnt/photos/                  → NFS, not local
  /mnt/backups/                 → NFS, not local
  ```
- [ ] Confirm: no data on k4 that doesn't exist elsewhere
- [ ] Power off: `ssh root@192.168.20.64 'poweroff'`
- [ ] Physically unplug and label as spare/retired

---

## Phase 8: Smoke test everything

After all machines are retired, run this final checklist:

### Public services (from outside LAN)

- [ ] `https://homeassistant.crussell.io` — HA loads
- [ ] `https://jellyfin.crussell.io` — Jellyfin loads, library browsable
- [ ] `https://photos.crussell.io` — Immich loads, photos visible
- [ ] `https://datenight.crussell.io` — Datenight loads

### Internal services (via Nebula or LAN)

- [ ] `https://ntfy.internal.crussell.io` — ntfy works, test push
- [ ] `https://search.internal.crussell.io` — SearXNG search works
- [ ] `https://linkding.internal.crussell.io` — Bookmarks present
- [ ] `https://papra.internal.crussell.io` — Documents present
- [ ] `https://open-webui.internal.crussell.io` — Chat history present

### Media stack

- [ ] Sonarr: series list intact, connections to Prowlarr and qBittorrent green
- [ ] Radarr: movies intact, connections green
- [ ] Prowlarr: indexers connected
- [ ] qBittorrent: all torrents seeding, no errors
- [ ] Jellyseerr: connected to Jellyfin

### Dev stack (bee)

- [ ] Gloo infra: postgres, rustfs, pgadmin running
- [ ] Gloo app services: all 6 dev servers responding
- [ ] Caddy routes: `gpl.internal.crussell.io`, `polymer.internal.crussell.io`, etc. all resolve

### Infrastructure

- [ ] Nebula: all nodes connect (think, bee, bees, gateway)
- [ ] NFS: `/mnt/media`, `/mnt/photos`, `/mnt/backups` mounted on bees
- [ ] NFS: `/mnt/backups` mounted on bee
- [ ] DNS: all public domains resolve
- [ ] TLS: all certs valid (check expiry dates)

---

## Data transfer size summary

| Source | Total data to transfer | Method |
|--------|----------------------|--------|
| k3 media services | ~12 GB | rsync over Nebula or LAN |
| k4 Immich + postgres | ~395 MB | rsync over Nebula or LAN |
| k2 hub services + Caddy | ~13 GB | rsync over Nebula or LAN |
| k1 Gloo source + volumes | ~2 GB + volumes | rsync over Nebula or LAN |
| **Total** | **~28 GB** | ~30 min on 1GbE, ~3 min on 10GbE |

All media/photo files stay on the NAS — only config/state databases move.

---

## Rollback plan

If something goes wrong during migration:

1. **Keep k1-k4 powered off but physically connected** for 2 weeks
2. All data remains on their disks — just power them back on and start services
3. If using Option A (bees took 10.10.0.6): swap Nebula certs back to k2, restart k2 services
4. If using Option B: update gateway to point back to 10.10.0.6

After 2 weeks of stable operation on bees + bee, wipe and repurpose or sell k1-k4.

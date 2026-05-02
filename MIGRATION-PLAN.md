# Infrastructure Migration Plan

**Goal:** Move all servers to NixOS with a unified flake, zero data loss, minimal downtime.

---

## Current State Summary

| Host | IP | OS | Role | Status |
|------|-----|-----|------|--------|
| hub | 192.168.20.105 | Fedora Atomic | Main server (Caddy, 15+ services) | Needs migration |
| k1 | 192.168.20.61 | Fedora Server 42 | Old media server (containers still running) | Reformat → NixOS |
| k2 | 192.168.20.62 | NixOS 25.11 | Utility (Docker, beszel agent) | Needs disk reformat |
| k3 | 192.168.20.26 | NixOS 25.11 | Media server (native services) | **Change IP to .63** |
| k4 | 192.168.20.64 | NixOS 25.11 | Immich + Beszel hub + chex-mix-timer | Needs disk reformat |
| nas | 192.168.20.31 | TrueNAS | NFS storage | Possible migration (last) |
| gateway | 178.156.171.212 | Fedora | VPS nginx passthrough | Unchanged |
| think | — | NixOS | Laptop | Already done |

### Key Data Volumes to Preserve

| Location | Data | ~Size |
|----------|------|-------|
| hub `/srv/immich` | Immich postgres data | Small (4K — actual photos on NAS NFS) |
| hub `/srv/open-webui` | Chat history | 1.1G |
| hub `/srv/linkding` | Bookmarks | 440K |
| hub `/srv/papra` | Documents | 14M |
| hub `/srv/searxng` | Search config | 88K |
| hub `/srv/datenight` | App data | 4K |
| hub `/srv/ntfy` | Notification cache | 0 |
| hub `/home/crussell/` | Dotfiles, code, SSH keys, age key | Unknown (du timed out — investigate) |
| hub containers | Gloo postgres, Buildspace postgres, RustFS | In podman storage (~471G total on disk) |
| k4 docker volumes | Immich postgres+redis+model-cache | 2.2G |
| k3 `/var/lib/{jellyfin,sonarr,radarr,prowlarr,jellyseerr,qbittorrent}` | Media configs | Small |
| k3 `/mnt/media` | NFS from NAS — media files | On NAS, safe |
| k2 `/var/lib/longhorn` (sda) | Longhorn storage (72G used) | Can wipe if longhorn is deprecated |
| k4 `/var/lib/longhorn` (sda) | Longhorn storage (48G used) | Can wipe if longhorn is deprecated |

### Disk Layouts (all Elitedesk — identical hardware: 238G NVMe + 1.8T HDD)

**Current:**
- **k2:** 1G EFI + ext4 root on NVMe; ext4 `/var/lib/longhorn` on HDD
- **k4:** 1G EFI + ext4 root on NVMe; ext4 `/var/lib/longhorn` on HDD
- **k3:** 512M EFI + 8G swap + ext4 root on NVMe; ext4 `/mnt/data` on HDD
- **k1:** Fedora LVM on NVMe; `/mnt/vms` (150G) + `/mnt/longhorn` on HDD

**Proposed standard layout (all k-machines):**
```
NVMe: 1G EFI + 16G swap (match RAM) + btrfs root (with @/ @/home subvols)
HDD: ext4 /mnt/data
```
> btrfs gives you send/receive for snapshots, transparent compression, and easy rollbacks.
> swap matches 16G RAM for hibernate if ever needed.

---

## Phase 0: Unified Flake Setup & Deploy Automation

**Before touching any hardware, set up the repo structure that all machines will use.**

### 0.1 Create unified flake in this repo

Consolidate the k2/k4 configs (currently on `~/cn/` on k2) and the k3 config into a single flake here:

```
cn/
├── flake.nix              # Single flake: outputs for k1, k2, k3, k4, hub, think, nas
├── flake.lock
├── hosts/
│   ├── k1/configuration.nix
│   ├── k2/configuration.nix
│   ├── k3/configuration.nix      # (move from servers/k3/)
│   ├── k4/configuration.nix
│   ├── hub/configuration.nix
│   └── think/configuration.nix   # (move from thinkpad/)
├── modules/                      # Shared NixOS modules
│   ├── elitedesk.nix             # Common hardware for k1-k4
│   ├── base-server.nix           # SSH, users, nix settings, base packages
│   ├── media-services.nix        # Jellyfin/*arr stack (k3)
│   ├── nebula-client.nix         # Nebula VPN client config
│   ├── caddy-proxy.nix           # Caddy reverse proxy (hub)
│   └── monitoring.nix            # Beszel agent
├── disk-configs/
│   └── elitedesk.nix             # Standard disk layout for all k-machines
├── secrets/                      # agenix secrets
└── ...
```

**Key principle:** Every machine builds from the same flake. `nixosConfiguration` outputs for each host. Shared modules DRY up common config.

### 0.2 Set up remote deploy strategy

**Recommended: `nixos-rebuild switch --target-host` (built-in, no extra tools)**

From your thinkpad (or any machine with the flake):

```bash
# Build and push config to remote machine
nixos-rebuild switch --flake .#k3 --target-host root@192.168.20.63

# Or with SSH config:
nixos-rebuild switch --flake .#k3 --target-host k3
```

This works because:
- Nix builds the closure locally (or on a remote builder)
- `nix-copy-closure` pushes it to the target
- `nixos-rebuild` activates it on the target

**Alternative worth considering:** Add a `deploy` script or use `colmena` if you want parallel deploys.

**SSH config** (`~/.ssh/config` on thinkpad):
```
Host k1 k2 k3 k4 hub
    User crussell
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

Host k3
    HostName 192.168.20.63

Host k2
    HostName 192.168.20.62

Host k4
    HostName 192.168.20.64
```

> **Note:** For `nixos-rebuild --target-host` to work with `crussell`, you need passwordless sudo on the target (which all your configs already set). Alternatively, use `root@host` as the target.

### 0.3 Clean up deprecated directories

- Remove `crussell-srv/` (Fedora bootc image builder — no longer needed)
- Remove `brunch/` (replaced by NixOS declarative config)
- Archive `servers/media/quadlets/` if it exists anywhere
- Update `AGENTS.md` to remove all brunch/crussell-srv references

---

## Phase 1: k3 IP Change (192.168.20.26 → 192.168.20.63)

**Risk: LOW** — k3 is already NixOS, just an IP change. All media services are native.

### 1.1 Update k3 NixOS config

In `hosts/k3/configuration.nix` (or current `servers/k3/configuration.nix`):
```nix
networking.interfaces.eno1.ipv4.addresses = [{
  address = "192.168.20.63";
  prefixLength = 24;
}];
```

### 1.2 Update all references across the repo

Files to update:
- `servers/k3/README.md` — IP references
- `servers/k3/hardware-configuration.nix` — if IP is there
- `servers/hub/caddy/routes/internal/media.caddy` — `192.168.20.26` → `192.168.20.63`
- `servers/hub/caddy/routes/internal/gloo.caddy` — `192.168.20.26` → `192.168.20.63`
- `AGENTS.md` — machine registry
- `nebula/configs/` — if k3 has a nebula config
- `servers/hub/caddy/Caddyfile` — jellyfin public route
- Any SSH config references

### 1.3 Deploy

```bash
# Apply the IP change on k3
nixos-rebuild switch --flake .#k3 --target-host root@192.168.20.26
# (network will drop — reconnect on .63)

# Update and reload Caddy on hub
# (edit Caddy routes, validate, reload)
```

### 1.4 Verify
- SSH to `192.168.20.63`
- Test all media services
- Test Caddy routes (internal and public jellyfin)

---

## Phase 2: k1 → NixOS (Reformat)

**Risk: LOW** — k1 is the old media server, its containers are still running but all data has already been migrated to k3. The only thing on k1 is Fedora + podman containers pointing at NFS.

### 2.1 Verify k1 is safe to wipe

```bash
# Confirm k3 services are running and healthy
ssh 192.168.20.63  # (after Phase 1)
systemctl status jellyfin sonarr radarr prowlarr jellyseerr qbittorrent
```

### 2.2 Stop and disable k1 containers

```bash
ssh crussell@192.168.20.61
podman stop -a
podman system prune -af
```

### 2.3 Install NixOS via nixos-anywhere

From thinkpad (or k4):
```bash
nixos-anywhere --flake .#k1 root@192.168.20.61
```

Uses the standard elitedesk disk config (wipes both NVMe and HDD).

### 2.4 Configure k1 role

k1 becomes a general-purpose NixOS node. Possible roles:
- Spare compute / future service host
- Docker/Podman host for migrating hub services to during hub migration
- Backup Immich instance

### 2.5 Verify
- SSH to `192.168.20.61`
- Confirm basic services (SSH, monitoring agent)

---

## Phase 3: k2 & k4 Disk Reformat (Standardize Layout)

**Risk: MEDIUM** — k4 has running Immich and chex-mix-timer containers with data.

### 3.1 Migrate k4 services to k1 (now NixOS)

Since k1 is freshly installed NixOS with standard layout:

1. **Immich on k4 (Docker):** The immich_server container is in a restart loop. Data is only 2.2G in volumes. Move to k1 as native NixOS services or Docker Compose.
   - `immich-pgdata` → dump postgres, restore on k1
   - `immich-model-cache` → just re-downloads
   - Photo storage is on NFS (`/mnt/nas/photos`), so no data risk

2. **chex-mix-timer on k4:** Container + redis data. Small. Move to k1.

3. **Beszel hub on k4:** Move to k1 or hub.

### 3.2 Reformat k4

```bash
nixos-anywhere --flake .#k4 root@192.168.20.64
```

Standard elitedesk disk layout. Services are now on k1.

### 3.3 Reformat k2

k2 only has longhorn data (deprecated) and beszel agent:
```bash
nixos-anywhere --flake .#k2 root@192.168.20.62
```

### 3.4 Redistribute services

After all k-machines have standard layout, assign service roles:

| Host | IP | Role | Services |
|------|-----|------|----------|
| k1 | 192.168.20.61 | App host | Immich, chex-mix-timer, Beszel hub |
| k2 | 192.168.20.62 | Utility | Beszel agent, spare capacity |
| k3 | 192.168.20.63 | Media | Jellyfin, *arr stack, qBittorrent, Gloo |
| k4 | 192.168.20.64 | Utility | Beszel agent, spare capacity |

---

## Phase 4: Hub Migration to NixOS

**Risk: HIGH** — Hub is the central server with 15+ services, reverse proxy, and VPN.

### 4.1 Pre-migration: Audit and backup hub

```bash
# Full inventory of what needs to be preserved
ssh hub
# 1. Home directory
du -sh /home/crussell/*/ /home/crussell/.*/  2>/dev/null | sort -rh

# 2. All /srv volumes (already backed up via restic)
sudo du -sh /srv/*

# 3. Container volumes
podman volume ls

# 4. Quadlet configs (in repo, safe)
ls ~/.config/containers/systemd/

# 5. Caddy data (certs, config — in repo + volumes)

# 6. Nebula certs and configs (in repo + /etc/nebula/)

# 7. Restic backup config (/etc/restic/)

# 8. Age key (~/.config/age/key.txt) — CRITICAL for decrypting secrets

# 9. SSH keys (~/.ssh/)

# 10. Gloo dev stack secrets and data
```

**Create a pre-migration backup snapshot:**
```bash
sudo systemctl start restic-backup.service
# Verify snapshot
sudo restic snapshots --repo /var/mnt/tank/backups/hub-restic --password-file /etc/restic/password
```

### 4.2 Pre-migration: Move Caddy to a k-machine

**Strategy: Temporary Caddy on a k-machine so public routes stay up while hub is down.**

1. Deploy Caddy on k1 (or k4) with the same routes pointing to backends:
   - Internal services that are on k-machines: just point to them
   - Services that were on hub (linkding, papra, etc.): they'll be down during migration

2. Update Route53 / DNS to point to the new Caddy if needed (or just update the Nebula routing)

3. **Public routes that matter during migration:**
   - `jellyfin.crussell.io` → k3 (already there, no change)
   - `homeassistant.crussell.io` → HA (no change)
   - `photos.crussell.io` → Immich on k1 (already migrated)
   - Everything else can be briefly down

### 4.3 Pre-migration: Move hub-specific services to k-machines

Services that can move before hub goes down:

| Service | Where | How |
|---------|-------|-----|
| Buildspace postgres | k1 or k4 | Docker compose or native |
| Gloo stack | Already on k3 | Verify |
| Datenight | k1 | Small app, easy to move |
| OpenCode web | k1 | Simple service |

### 4.4 Migrate hub to NixOS

1. **Ensure restic backup is current**
2. **Note the hub disk:** 931.5G NVMe, btrfs (Fedora Atomic). 471G used.

```bash
# From thinkpad
nixos-anywhere --flake .#hub root@192.168.20.105
```

This will reformat the disk. The hub NixOS config should include:
- Caddy (with all routes restored)
- Nebula (both lighthouse and host identity)
- Restic backup (pointing to same NAS repo)
- All hub services as NixOS modules or OCI containers

### 4.5 Restore hub data

```bash
# After NixOS is installed on hub
sudo restic restore latest --target / --repo /var/mnt/tank/backups/hub-restic --password-file /etc/restic/password --include /srv/
```

### 4.6 Verify hub

- Caddy routes all working
- Nebula up (both identities)
- All services running
- Backup timer active

---

## Phase 5: NAS Migration (Optional, Last)

**Risk: VERY HIGH** — This is where all the data lives.

### 5.1 Decision point

**Arguments FOR migrating NAS to NixOS:**
- Declarative config for NFS exports, ZFS pools, SMB shares
- Unified management with the rest of the fleet
- No more TrueNAS web UI dependency

**Arguments AGAINST:**
- TrueNAS works well and is purpose-built for storage
- Risk of data loss is highest here
- ZFS on NixOS is mature but TrueNAS provides a nice safety net
- Time investment is large

**Recommendation:** Skip for now. Revisit when TrueNAS causes pain or you want to learn ZFS on NixOS. The NAS can remain TrueNAS indefinitely — it's just an NFS server from the perspective of everything else.

If you do decide to do it:
1. Back up everything (you'd need a second NAS or large external drive)
2. Install NixOS with ZFS
3. Import pools
4. Set up NFS exports declaratively

---

## Phase 6: Gateway Migration (Optional)

The gateway (Hetzner VPS) runs simple nginx SSL passthrough. Could easily be NixOS, but it's also fine on Fedora. Low priority since it's a single simple config file. Can be done at any time.

---

## Execution Order Summary

```
Phase 0: Unified flake + deploy automation       [1-2 days]
    ↓
Phase 1: k3 IP change (.26 → .63)               [1 hour]
    ↓
Phase 2: k1 → NixOS (wipe, fresh install)        [1-2 hours]
    ↓
Phase 3: k4 migrate services → k1, reformat k4   [2-3 hours]
         Reformat k2                              [1 hour]
    ↓
Phase 4: Hub migration                           [full day]
         (audit → backup → move services → install → restore)
    ↓
Phase 5: NAS (optional, later)                   [??]
```

## Open Questions (RESOLVED)

1. ~~**Hub home directory**~~ → Everything backed up to `$HOME/backup/` (age key, SSH keys, nebula certs, quadlets, restic password, 360 project code)
2. ~~**Longhorn**~~ → Not used anywhere, completely removed. All `/var/lib/longhorn` mounts can be wiped.
3. ~~**Immich on k4**~~ → Server container in restart loop. Will set up fresh on k1 during migration.
4. ~~**Gloo**~~ → Active on k3 (native NixOS module). Hub gloo dev servers will be shut down. Will eventually move gloo to k1 or k2.
5. ~~**NAS NFS exports**~~ → `tank/media`, `tank/photos`, `tank/backups` are the known ones.
6. ~~**Nebula on k-machines**~~ → Yes, all k-machines get Nebula client. Module is ready, just needs certs deployed.
7. ~~**Age key**~~ → Copied to `$HOME/backup/age/` on hub.
8. ~~**`crussell-srv`**~~ → Deprecated, to be removed.
9. ~~**`brunch`**~~ → Deprecated, to be removed.

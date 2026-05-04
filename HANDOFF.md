# Handoff: Infrastructure Migration Progress

**Date:** 2026-05-02
**Repo:** `/home/crussell/Code/cn` (github.com:chad-russell/cn)

---

## Current Fleet State

| Host | IP | OS | Disk Layout | Remote Deploy | Status |
|------|-----|-----|------------|--------------|--------|
| hub | 192.168.20.105 | Fedora Atomic | btrfs (931G NVMe) | ❌ N/A | Needs migration (Phase 4) |
| k1 | 192.168.20.61 | NixOS 25.11 ✅ | Standard ✅ | ✅ Works | Clean install, empty |
| k2 | 192.168.20.62 | NixOS 25.11 ✅ | Standard ✅ | ✅ Works | Clean install, empty |
| k3 | 192.168.20.63 | NixOS 25.11 ✅ | Original (512M/8G/ext4) ✅ | ⚠️ Not tested remotely | Running media + gloo services |
| k4 | 192.168.20.64 | NixOS 25.11 ✅ | Standard ✅ | ✅ Works | Clean install, empty |
| gateway | 178.156.171.212 | Fedora | N/A | N/A | Unchanged |
| nas | 192.168.20.31 | TrueNAS | ZFS | N/A | Unchanged |
| think | — | NixOS 25.11 | Own layout | Local rebuild | Your laptop |

### "Standard" Disk Layout (k1, k2, and all future installs)

```
NVMe (/dev/nvme0n1): 512M EFI (vfat) + 8G swap + ext4 root
HDD  (/dev/sda):     ext4 /mnt/data
```

Defined in: `modules/elitedesk-disk-config.nix`

### k3 Exception

k3 was installed before the unified flake and has the same *sizes* but different disko naming (`main` vs `nvme0`, `ESP` vs `boot`). It works fine. Config uses `servers/k3/disk-config.nix` (the original). **Do NOT switch k3 to the standard disk config without reformatting it** — the partition names must match the actual disk.

---

## What's Done

### ✅ Phase 0: Unified Flake

Single flake at repo root with all host configs:

```
cn/
├── flake.nix                    # Unified flake for ALL hosts
├── hosts/
│   ├── k1/configuration.nix     # Clean NixOS, standard layout
│   ├── k2/configuration.nix     # Clean NixOS, standard layout
│   ├── k3/                      # Media server (original layout)
│   │   ├── configuration.nix
│   │   ├── media-services.nix   # Jellyfin/*arr/qBittorrent
│   │   ├── gloo.nix             # Gloo dev stack module
│   │   └── gloo/                # Compose + env files
│   ├── k4/configuration.nix     # Still on old layout, needs reformat
│   └── hub/configuration.nix    # Placeholder
├── modules/
│   ├── base-server.nix          # Shared: users, SSH, networkd, packages
│   ├── elitedesk-hardware.nix   # Hardware imports + common boot
│   ├── elitedesk-hardware-quirks.nix  # e1000e NIC fixes, watchdog
│   ├── elitedesk-disk-config.nix      # Standard disk layout
│   └── nebula-client.nix        # Nebula VPN (ready, certs not deployed)
├── secrets/
│   └── gloo-secrets.env.age
└── thinkpad/                    # Separate structure (home-manager, etc.)
```

**Deploy commands:**
```bash
# Remote deploy to any server (builds locally, pushes over SSH):
nixos-rebuild switch --flake .#k1 --target-host crussell@192.168.20.61 --sudo

# Fresh install via nixos-anywhere (WIPES DISK):
nix run github:nix-community/nixos-anywhere -- \
  --flake .#k2 -i ~/.ssh/id_ed25519 --ssh-option IdentitiesOnly=yes --build-on local \
  crussell@192.168.20.62

# Local rebuild (thinkpad):
sudo nixos-rebuild switch --flake .#think
```

**Deprecated and removed:** `crussell-srv/`, `brunch/`, `crussell-fin/`

### ✅ Phase 1: k3 IP Change (192.168.20.26 → 192.168.20.63)

- k3 config updated with new IP
- All Caddy routes on hub updated (media.caddy, gloo.caddy, Caddyfile)
- AGENTS.md machine registry and architecture diagram updated

### ✅ Phase 2: k1 → NixOS

- `nixos-anywhere` installed NixOS with standard layout
- Clean install, no services yet

### ✅ Phase 3a: k2 Reformatted to Standard Layout

- First install used old per-host disk-config (wrong layout)
- Reinstalled with standard `elitedesk-disk-config.nix`
- Remote deploy verified working

---

## Next Steps

### ✅ Phase 3b: k4 Reformat

- Reinstalled with `nixos-anywhere` using standard `elitedesk-disk-config.nix`
- Removed `hosts/k4/disk-config.nix`, switched config to standard layout
- Removed `/mnt/photos` NFS mount (Immich moved to hub)
- Remote deploy verified working
- All old services removed: Docker, Tailscale, Immich, Beszel hub, chex-mix-timer
- Caddy route for chex-mix-timer commented out, Caddy reloaded on hub

### Phase 4: Hub Migration to NixOS

**The big one. Hub is the central server.**

What's running on hub (Fedora Atomic, 931G btrfs NVMe, 471G used):
- Caddy reverse proxy (all routes)
- Nebula VPN (dual identity: lighthouse 10.10.0.1 + host 10.10.0.6)
- Restic backup (daily → NAS)
- Podman containers: linkding, ntfy, papra, open-webui, datenight, searxng
- Dev stacks: Gloo compose (postgres, rustfs, pgadmin), Buildspace postgres
- User services: opencode-web, gloo dev servers (hb-api, hb-web, storyhub, storyhub-worker, polymer)

**Hub backup is already done** — everything critical is in `~/backup/` on hub:
- `age/` — age encryption key (CRITICAL)
- `ssh-keys/` — SSH keys (ed25519 + RSA)
- `nebula/` + `nebula-lh/` — both Nebula identity certs/configs
- `restic-password`
- `quadlets/` — current systemd container units
- `360-dreamstack-*` — project code

**Hub migration plan:**
1. Add service configs to `hosts/hub/configuration.nix` (Caddy, Nebula, containers, restic)
2. Move what can move to k-machines before wiping hub
3. Ensure restic snapshot is current
4. `nixos-anywhere` hub — **expect full downtime for reverse proxy during this**
5. Restore /srv data from restic
6. Verify all services

**Hub has a unique disk** (931G NVMe, not the 238G Elitedesk NVMe). Will need its own disk-config, not the elitedesk one.

### Phase 5: NAS (Optional, Last)

TrueNAS → NixOS with ZFS. High risk, low urgency. Skip for now.

---

## Known Issues & Gotchas

### SSH Key

The thinkpad's current ed25519 key (`OpNEpdHo...`) is now in `base-server.nix`. The old key (`LQwJo2dY...`) was removed. If any machine was set up with the old key, you'll need `ssh-copy-id` to add the new one.

### Remote Deploy `require-sigs`

Machines installed via our unified flake have `trusted-users = ["root" "crussell"]`, so `nix-copy-closure` works as crussell. The old k2/k4 installs from the remote repo did NOT have this, which would have blocked remote deploy. All machines are now on our flake so this is resolved.

### nixos-rebuild switch for IP changes

**NEVER use `switch` for IP/network changes over SSH.** It changes the network config mid-session, drops SSH, and leaves the machine in a half-activated state. Use `boot` instead:
```bash
# On the machine:
sudo nixos-rebuild boot --flake .#hostname
sudo reboot
```

### k3 Still Has Remote Repo

k3 has `~/cn/` which is a separate git repo (the old cluster repo). The unified flake in *this* repo is the source of truth now. When deploying to k3, either:
- SSH in, `cd ~/cn && git pull && sudo nixos-rebuild switch --flake .#k3` (uses the remote repo)
- Or test remote deploy: `nixos-rebuild switch --flake .#k3 --target-host crussell@192.168.20.63 --sudo`

### Thinkpad on WiFi

The thinkpad's ethernet (`enp0s31f6`) is DOWN. It's on WiFi (`wlp0s20f3` at 192.168.20.27). This causes flaky connectivity to LAN servers. Consider plugging in ethernet for large file transfers.

### Elitedesk e1000e NIC

All k-machines have the Intel I219-LM NIC with known "Hardware Unit Hang" issues. The `elitedesk-hardware-quirks.nix` module disables offloading and forces PCIe ASPM off. SSH comes up slowly after boot (~60-90s) because of this.

---

## Caddy Routes Reference

All routes live in `servers/hub/caddy/`. Reload with:
```bash
ssh hub "sudo podman exec systemd-caddy caddy validate --config /etc/caddy/Caddyfile && \
  sudo podman exec systemd-caddy caddy reload --config /etc/caddy/Caddyfile"
```

| Route | Backend | File |
|-------|---------|------|
| jellyfin.crussell.io | k3:8096 | Caddyfile |
| homeassistant.crussell.io | 192.168.20.51:8123 | Caddyfile |
| photos.crussell.io | hub:30093 | Caddyfile |
| ~~chex-mix-timer.crussell.io~~ | ~~k4:8732~~ | ~~Caddyfile~~ (removed) |
| qbittorrent/sonarr/radarr/prowlarr/jellyseerr/jellyfin internal | k3 (.63) | routes/internal/media.caddy |
| gpl/hb-api/hb-web/polymer/rustfs/pgadmin/storyhub internal | k3 (.63) | routes/internal/gloo.caddy |
| linkding/papra/ntfy/searxng/openwebui internal | hub (127.0.0.1) | routes/internal/hub-services.caddy |
| buildspace/bs-* internal | hub (127.0.0.1) | routes/internal/buildspace.caddy |
| opencode internal | hub (127.0.0.1) | routes/internal/opencode.caddy |

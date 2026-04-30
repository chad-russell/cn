# k3: ext4 → btrfs Migration Plan

**Status:** Planning — not yet approved  
**Downtime estimate:** 1–3 hours  
**Prerequisites:** Helper NixOS machine at `192.168.20.62` with enough disk space for backup (~50G should be plenty; service data is mostly small SQLite DBs + configs, Jellyfin metadata is the wild card)

---

## Overview

Reformat k3's NVMe (`/dev/nvme0n1`) from ext4 root to btrfs with subvolumes. The data HDD (`/dev/sda`) stays ext4 but will be reformatted by disko (it's currently unused). We'll use the same `nixos-anywhere` workflow as the original install.

```
BEFORE (current):                        AFTER (target):
/dev/nvme0n1:                            /dev/nvme0n1:
  EFI (512M)                               EFI (512M)
  swap (8G)                                swap (8G)
  ext4 root (rest)                         btrfs:
                                             @  → /
                                             @nix → /nix
                                             @var → /var
                                             @home → /home

/dev/sda:                                /dev/sda:
  ext4 → /mnt/data (unused)               ext4 → /mnt/data (fresh format)
```

---

## Phase 0: Pre-flight (on your local machine, no downtime)

### 0.1 — Prepare the new disk-config.nix

Replace `servers/k3/disk-config.nix` with the btrfs layout. The new file will declare both disks (NVMe + HDD) under disko, so the manual `fileSystems."/mnt/data"` in `configuration.nix` must be **removed** — disko will generate the mount unit.

```nix
# disk-config.nix — new btrfs layout
{
  disko.devices = {
    disk = {
      main = {
        device = "/dev/nvme0n1";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            swap = {
              size = "8G";
              content = {
                type = "swap";
                resumeDevice = true;
              };
            };
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "@" = {
                    mountpoint = "/";
                    mountOptions = [ "compress=zstd" "noatime" ];
                  };
                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = [ "compress=zstd" "noatime" ];
                  };
                  "@var" = {
                    mountpoint = "/var";
                    mountOptions = [ "compress=zstd" "noatime" ];
                  };
                  "@home" = {
                    mountpoint = "/home";
                    mountOptions = [ "compress=zstd" "noatime" ];
                  };
                };
              };
            };
          };
        };
      };
      data = {
        device = "/dev/sda";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            data = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/mnt/data";
              };
            };
          };
        };
      };
    };
  };
}
```

### 0.2 — Edit configuration.nix

Remove this block (disko will manage it now):

```nix
  # ── Local HDD ───────────────────────────────────────
  fileSystems."/mnt/data" = {
    device = "/dev/disk/by-uuid/e9c12a3f-6a65-458f-bd9b-ac46537e8839";
    fsType = "ext4";
    options = [ "defaults" "nofail" ];
  };
```

No other changes needed — service configs, users, NFS mount, etc. all stay the same.

### 0.3 — Commit and push

```bash
cd ~/Code/cn
git add servers/k3/disk-config.nix servers/k3/configuration.nix
git commit -m "k3: switch disk-config to btrfs subvolumes"
git push
```

### 0.4 — Estimate backup size on k3

```bash
ssh k3 'sudo du -sh /var/lib/jellyfin /var/lib/sonarr /var/lib/radarr /var/lib/prowlarr /var/lib/jellyseerr /var/lib/qBittorrent /home/crussell /etc/ssh'
```

Verify the helper machine (.62) has enough space. The big unknown is Jellyfin metadata.

---

## Phase 1: Backup to helper machine (downtime begins)

Run from the helper machine (`192.168.20.62`), or from k3 pushing to .62.

### 1.1 — Stop all services on k3

```bash
ssh k3 'sudo systemctl stop jellyfin sonarr radarr prowlarr jellyseerr qbittorrent'
# Also stop gloo if it's running
ssh k3 'sudo systemctl stop gloo-docker-compose.service 2>/dev/null; true'
```

### 1.2 — Create backup directory on helper

```bash
ssh 192.168.20.62 'mkdir -p /tmp/k3-backup'
```

### 1.3 — rsync all service data to helper

```bash
HELPER="crussell@192.168.20.62"
SSH_KEY="-i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes"
DEST="$HELPER:/tmp/k3-backup"

# Service data
ssh $SSH_KEY k3 'sudo tar cf - /var/lib/jellyfin'      | ssh $SSH_KEY $DEST 'cat > jellyfin.tar'
ssh $SSH_KEY k3 'sudo tar cf - /var/lib/sonarr'        | ssh $SSH_KEY $DEST 'cat > sonarr.tar'
ssh $SSH_KEY k3 'sudo tar cf - /var/lib/radarr'        | ssh $SSH_KEY $DEST 'cat > radarr.tar'
ssh $SSH_KEY k3 'sudo tar cf - /var/lib/prowlarr'      | ssh $SSH_KEY $DEST 'cat > prowlarr.tar'
ssh $SSH_KEY k3 'sudo tar cf - /var/lib/jellyseerr'    | ssh $SSH_KEY $DEST 'cat > jellyseerr.tar'
ssh $SSH_KEY k3 'sudo tar cf - /var/lib/qBittorrent'   | ssh $SSH_KEY $DEST 'cat > qbittorrent.tar'

# User home
ssh $SSH_KEY k3 'sudo tar cf - /home/crussell'         | ssh $SSH_KEY $DEST 'cat > home-crussell.tar'

# SSH host keys (prevents "host key changed" warnings)
ssh $SSH_KEY k3 'sudo tar cf - /etc/ssh'               | ssh $SSH_KEY $DEST 'cat > etc-ssh.tar'

# Age key for agenix (needed to decrypt secrets at build time)
ssh $SSH_KEY k3 'sudo tar cf - /home/crussell/.config/age 2>/dev/null; true' | ssh $SSH_KEY $DEST 'cat > age-key.tar'
```

> **Why tar over rsync?** tar preserves ownership perfectly (`root:jellyfin` etc.) in a single stream. With rsync you'd need `--rsync-path='sudo rsync'` or root SSH, which is messier.

### 1.4 — Verify backup integrity

```bash
ssh $SSH_KEY $DEST 'ls -lh /tmp/k3-backup/'
# Quick sanity: list contents of each tar
ssh $SSH_KEY $DEST 'for f in /tmp/k3-backup/*.tar; do echo "=== $f ==="; tar tf "$f" | head -5; echo; done'
```

---

## Phase 2: Reinstall via nixos-anywhere (from helper machine)

This is the same workflow used for the original k3 install. Run from `192.168.20.62`.

### 2.1 — Ensure nixos-anywhere is available on helper

```bash
# On 192.168.20.62
nix run github:numtide/nixos-anywhere -- --help
```

Or if already installed:
```bash
nixos-anywhere --help
```

### 2.2 — Clone/pull the repo on helper

```bash
ssh 192.168.20.62
cd ~/cn  # or wherever
git pull
# If not cloned yet:
# git clone <your-repo-url> ~/cn
```

### 2.3 — Run nixos-anywhere

```bash
# From 192.168.20.62
nixos-anywhere \
  --flake ~/cn/servers/k3#k3 \
  --target-host root@192.168.20.26 \
  --build-on-remote
```

> **What this does:**
> 1. SSHs into k3, runs `kexec` to boot a NixOS installer in RAM
> 2. Runs `disko` to partition/format both disks (wipes NVMe + HDD)
> 3. Generates hardware config
> 4. Runs `nixos-install` with the flake
> 5. Reboots into the new system

> **⚠️ This destroys everything on `/dev/nvme0n1` and `/dev/sda`. The backup is all we have.**

### 2.4 — Wait for reboot

After nixos-anywhere completes, k3 should reboot into a fresh NixOS with btrfs. Wait ~30 seconds, then verify:

```bash
ssh -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 crussell@192.168.20.26 'uname -a'
ssh -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 crussell@192.168.20.26 'findmnt -t btrfs'
ssh -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 crussell@192.168.20.26 'df -h'
```

You should see:
```
/dev/nvme0n1p3  /        btrfs  subvol=/@     ...
/dev/nvme0n1p3  /nix     btrfs  subvol=@nix  ...
/dev/nvme0n1p3  /var     btrfs  subvol=@var  ...
/dev/nvme0n1p3  /home    btrfs  subvol=@home ...
/dev/sda1       /mnt/data ext4  ...
```

---

## Phase 3: Restore from backup

Run from k3, pulling data from the helper machine.

### 3.1 — On k3, set up SSH to helper (if needed)

```bash
# k3's SSH key should survive if it's in the config, but fresh install = fresh host keys
# The backed-up SSH keys will be restored later, but for now:
ssh-keyscan 192.168.20.62 >> ~/.ssh/known_hosts
```

### 3.2 — Restore all data

```bash
HELPER="crussell@192.168.20.62"
SSH_KEY="-i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes"

# Pull tars from helper and extract on k3
ssh $SSH_KEY $HELPER 'cat /tmp/k3-backup/jellyfin.tar'    | sudo tar xf - -C /
ssh $SSH_KEY $HELPER 'cat /tmp/k3-backup/sonarr.tar'      | sudo tar xf - -C /
ssh $SSH_KEY $HELPER 'cat /tmp/k3-backup/radarr.tar'      | sudo tar xf - -C /
ssh $SSH_KEY $HELPER 'cat /tmp/k3-backup/prowlarr.tar'    | sudo tar xf - -C /
ssh $SSH_KEY $HELPER 'cat /tmp/k3-backup/jellyseerr.tar'  | sudo tar xf - -C /
ssh $SSH_KEY $HELPER 'cat /tmp/k3-backup/qbittorrent.tar' | sudo tar xf - -C /
ssh $SSH_KEY $HELPER 'cat /tmp/k3-backup/home-crussell.tar' | sudo tar xf - -C /
ssh $SSH_KEY $HELPER 'cat /tmp/k3-backup/etc-ssh.tar'     | sudo tar xf - -C /
ssh $SSH_KEY $HELPER 'cat /tmp/k3-backup/age-key.tar'     | sudo tar xf - -C /
```

### 3.3 — Fix ownership

```bash
# Service users were created by NixOS during install, but extracted files may have wrong UID/GID
# Re-chown everything to match the service users
sudo chown -R jellyfin:media /var/lib/jellyfin
sudo chown -R sonarr:media /var/lib/sonarr
sudo chown -R radarr:media /var/lib/radarr
sudo chown -R prowlarr:media /var/lib/prowlarr
sudo chown -R jellyseerr:media /var/lib/jellyseerr
sudo chown -R qbittorrent:media /var/lib/qBittorrent
sudo chown -R crussell:users /home/crussell

# SSH keys
sudo chown -R root:root /etc/ssh
```

### 3.4 — Restart SSH to pick up restored host keys

```bash
sudo systemctl restart sshd
```

> **⚠️ After this, SSH from other machines will match the old host keys again (no "host key changed" warning).**

### 3.5 — Rebuild to activate all services

```bash
cd ~/cn
git pull
sudo nixos-rebuild switch --flake ./servers/k3#k3
```

This will start all media services with their restored data.

### 3.6 — Verify all services are running

```bash
systemctl is-active jellyfin sonarr radarr prowlarr jellyseerr qbittorrent
```

---

## Phase 4: Verification checklist

### Services
- [ ] **Jellyfin** (http://192.168.20.26:8096) — libraries load, plays media
- [ ] **Sonarr** (http://192.168.20.26:8989) — series listed, connected to Prowlarr + qBittorrent
- [ ] **Radarr** (http://192.168.20.26:7878) — movies listed, connected to Prowlarr + qBittorrent
- [ ] **Prowlarr** (http://192.168.20.26:9696) — indexers listed, connected to Sonarr + Radarr
- [ ] **Jellyseerr** (http://192.168.20.26:5055) — loads, connected to Jellyfin + Sonarr + Radarr
- [ ] **qBittorrent** (http://192.168.20.26:8080) — torrents seeding, paths correct
- [ ] **Gloo** — if applicable

### Storage
- [ ] `findmnt -t btrfs` shows all 4 subvolumes mounted with `compress=zstd,noatime`
- [ ] `df -h` shows NVMe root pool with expected free space
- [ ] `/mnt/data` is mounted (ext4, empty — fresh format)
- [ ] `/mnt/media` NFS mount is working: `ls /mnt/media/`

### Btrfs health
```bash
# Check compression is active (should show compressed size < total)
sudo btrfs filesystem df /
sudo btrfs filesystem df /var
sudo compsize /var  # from pkgs.compsize, shows compression ratios
```

### Cleanup
- [ ] Delete backup from helper: `ssh 192.168.20.62 'rm -rf /tmp/k3-backup'`
- [ ] Update `servers/k3/README.md` to reflect new disk layout

---

## Rollback plan

If something goes wrong after Phase 2 (reinstall), the rollback is:

1. Re-run `nixos-anywhere` with the **old** `disk-config.nix` (ext4 layout)
2. Restore data from the backup on .62

The backup on .62 is your safety net. **Do not delete it until everything is verified.**

---

## Key risks and mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Jellyfin metadata is huge (>100G) | Backup takes too long or fills .62 | Check size in Phase 0.4 first. If too large, skip Jellyfin metadata and let it rescan (lossy but functional — watch history and custom metadata lost) |
| nixos-anywhere fails to kexec | Can't reinstall | Boot from USB installer instead; use `disko-install` manually |
| Data on `/dev/sda` is needed | It gets wiped | Currently unused per README. If this changes before migration, exclude it from disko or back it up too |
| Service UIDs don't match | Permission issues on restored files | Phase 3.3 re-chowns everything. NixOS creates deterministic UIDs for system users, but verify |
| btrfs corruption | Data loss | btrfs is stable for single-device use. Enable scrub timer: `services.btrfs.autoScrub.enable = true;` in configuration.nix |

---

## Optional: Add to configuration.nix for ongoing btrfs maintenance

```nix
  # btrfs maintenance
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };
```

This runs a metadata+data scrub once a month to catch silent corruption early.

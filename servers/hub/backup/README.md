# Hub Restic Backup System

Automated backups of container volumes and configs to NAS via Restic.

## Architecture

```
hub → NFS mount → /var/mnt/tank/backups/hub-restic (on NAS)
```

> **Note:** On Fedora Atomic, `/mnt` is a symlink to `/var/mnt`. Systemd requires canonical paths, so all paths use `/var/mnt`.

## What Gets Backed Up

| Path | Type | Notes |
|------|------|-------|
| `/srv/linkding/data` | Bind mount | Bookmarks |
| `/srv/papra/data` | Bind mount | Documents |
| `/srv/peekaping/data` | Bind mount | Uptime history |
| `/srv/audiobookshelf/config` | Bind mount | Server config |
| `/srv/audiobookshelf/metadata` | Bind mount | Play state |
| `/srv/adguardhome/conf` | Bind mount | DNS rules |
| `/srv/beszel/data` | Bind mount | Monitoring data |
| `/srv/open-webui/data` | Bind mount | Chat history |
| `/srv/mastra/data` | Bind mount | Studio traces and storage |
| `caddy_data` | Named volume | Certs (exported) |
| `caddy_config` | Named volume | Config (exported) |
| `/home/crussell/.config/containers/systemd` | Config | Quadlet files |
| `/home/crussell/Code/cn/nebula/pki` | Config | VPN certs |
| SQLite dumps | Dynamic | Hot backups of running DBs |

### Excluded

- `/srv/audiobookshelf/audiobooks/*` - Media files (on NAS already)
- `/srv/audiobookshelf/podcasts/*` - Media files
- `/srv/ntfy/cache/*` - Transient notification cache

## Retention Policy

- 7 daily backups
- 4 weekly backups  
- 12 monthly backups

## Installation

### 1. NAS Setup

On TrueNAS, create the backup dataset and NFS share:

```bash
# On TrueNAS web UI or CLI
zfs create tank/backups
zfs create tank/backups/hub-restic
```

Configure NFS export for `tank/backups` restricted to hub's IP (192.168.20.105).

### 2. Run Install Script

```bash
cd /home/crussell/Code/cn/servers/hub/backup
sudo ./install.sh
```

This installs:
- Restic package
- Password file at `/etc/restic/password`
- Backup script at `/usr/local/bin/restic-backup.sh`
- Systemd units for NFS mount and backup timer

### 3. Enable NFS Automount

```bash
sudo systemctl enable --now var-mnt-tank-backups.automount
```

### 4. Initialize Repository

```bash
sudo restic init --repo /var/mnt/tank/backups/hub-restic --password-file /etc/restic/password
```

### 5. Enable Timer

```bash
sudo systemctl enable --now restic-backup.timer
```

### 6. Subscribe to Notifications

```bash
# Subscribe to backup notifications
ntfy sub ntfy.internal.crussell.io/backups
```

## Manual Operations

### Run Backup Now

```bash
sudo systemctl start restic-backup.service
```

### Check Timer Status

```bash
systemctl status restic-backup.timer
systemctl list-timers
```

### View Backup Logs

```bash
journalctl -u restic-backup.service
```

### List Snapshots

```bash
sudo restic snapshots --repo /var/mnt/tank/backups/hub-restic --password-file /etc/restic/password
```

### Restore Files

```bash
# List files in latest snapshot
sudo restic ls latest --repo /var/mnt/tank/backups/hub-restic --password-file /etc/restic/password

# Restore specific path
sudo restic restore latest --target /tmp/restore --include /srv/linkding --repo /var/mnt/tank/backups/hub-restic --password-file /etc/restic/password
```

### Check Repository Stats

```bash
sudo restic stats --repo /var/mnt/tank/backups/hub-restic --password-file /etc/restic/password
```

## Files

| File | Purpose |
|------|---------|
| `restic-backup.sh` | Main backup script |
| `restic-backup.{service,timer}` | Systemd units for daily 2AM backups |
| `var-mnt-tank-backups.{mount,automount}` | NFS mount to NAS |
| `excludes` | Patterns to skip |
| `install.sh` | Automated deployment |

## Ntfy Topic

Backup notifications are sent to: `backups`

- Priority `default`: Successful backups
- Priority `urgent`: Failures

## Troubleshooting

### NFS Mount Issues

```bash
# Check mount
mountpoint /var/mnt/tank/backups

# Test manually
sudo mount -t nfs 192.168.20.31:/mnt/tank/backups /var/mnt/tank/backups
```

### Permission Issues

```bash
# Check password file permissions
ls -la /etc/restic/password

# Should be -rw------- root:root
```

### Restic Lock Issues

```bash
# Remove stale locks (only if no backup is running)
sudo restic unlock --repo /var/mnt/tank/backups/hub-restic --password-file /etc/restic/password
```

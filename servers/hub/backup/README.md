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
| `/srv/open-webui/data` | Bind mount | Chat history |
| `/srv/datenight/data` | Bind mount | Restaurant picks |
| `caddy_data` | Named volume | Certs (exported) |
| `caddy_config` | Named volume | Config (exported) |
| `/home/crussell/.config/containers/systemd` | Config | Quadlet files |
| `/home/crussell/Code/cn/nebula/pki` | Config | VPN certs |
| SQLite dumps | Dynamic | Hot backups of running DBs |

### Excluded

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

### 2. Install Restic

```bash
sudo dnf install -y restic
```

### 3. Provision Secrets And Credentials

Create the required local files on `hub`:

- `/etc/restic/password`
- `/etc/restic/aws/access_key`
- `/etc/restic/aws/secret_key`

Example password generation:

```bash
sudo mkdir -p /etc/restic /etc/restic/aws
sudo sh -c 'umask 077 && openssl rand -hex 32 > /etc/restic/password'
```

### 4. Apply The Hub Brunch Target

```bash
cd /home/crussell/Code/cn/brunch
brunch apply ./config --target hub
```

This installs the Brunch-managed backup assets:
- `/etc/restic/excludes`
- `/usr/local/bin/restic-backup.sh`
- `/usr/local/bin/restic-s3-copy.sh`
- systemd units for the NFS mount, automount, backup service, and timers

Apply with elevation when prompted so Brunch can install the system files and enable the managed units. Brunch enables:

- `var-mnt-tank-backups.automount`
- `restic-backup.timer`

`restic-s3-copy.timer` is installed but not enabled by default.

### 5. Initialize Repository

```bash
sudo restic init --repo /var/mnt/tank/backups/hub-restic --password-file /etc/restic/password
```

### 6. Optional: Enable Weekly S3 Copy

```bash
sudo systemctl enable --now restic-s3-copy.timer
```

### 7. Subscribe to Notifications

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
| `brunch/config/hosts/hub/backup.bri` | Brunch-managed systemd units and installed files |
| `brunch/config/hosts/hub/backup/restic-backup.sh` | Main backup script |
| `brunch/config/hosts/hub/backup/restic-s3-copy.sh` | Weekly S3 copy script |
| `brunch/config/hosts/hub/backup/excludes` | Patterns to skip |

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

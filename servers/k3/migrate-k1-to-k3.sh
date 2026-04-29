#!/usr/bin/env bash
# migrate-k1-to-k3.sh
# Migrate media service configs from k1 (Fedora/Podman) to k3 (NixOS/native)
#
# Run from k3 as root. k1 must be reachable via SSH as crussell.
#
# Path remapping:
#   Container /media  -> /mnt/media   (NFS mount)
#   Container /config -> varies by service on k3
#   Container /downloads -> /mnt/media/downloads
#
# Hostname remapping (container DNS -> localhost):
#   jellyfin -> 127.0.0.1
#   radarr   -> 127.0.0.1
#   sonarr   -> 127.0.0.1
#   prowlarr -> 127.0.0.1

set -euo pipefail

K1="crussell@192.168.20.61"
SSH_KEY="/home/crussell/.ssh/id_ed25519"
SSH_OPTS="-i $SSH_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
K1_SSH="ssh $SSH_OPTS $K1"

echo "==> Stopping all media services on k3..."
systemctl stop jellyfin sonarr radarr prowlarr jellyseerr qbittorrent

# ── Jellyfin ────────────────────────────────────────────────────
echo "==> Migrating Jellyfin..."
K1_JF="/home/crussell/.config/jellyfin"
K3_JF="/var/lib/jellyfin"

# Clear default NixOS jellyfin data
rm -rf "$K3_JF"/*

rsync -az -e "ssh $SSH_OPTS" "$K1:$K1_JF/" /tmp/jf-migrate/
# Restructure: k1 has config/, data/, log/, metadata/, plugins/, root/
# NixOS jellyfin expects: config/ (configdir), data in datadir root
# k1 layout already matches well — just copy it
cp -a /tmp/jf-migrate/* "$K3_JF/"
rm -rf /tmp/jf-migrate

# Fix media paths in Jellyfin DB and config (if any reference /media -> /mnt/media)
if [ -f "$K3_JF/config/system.xml" ]; then
  sed -i 's|/media/|/mnt/media/|g' "$K3_JF/config/system.xml"
fi

chown -R jellyfin:media "$K3_JF"

# ── Sonarr ──────────────────────────────────────────────────────
echo "==> Migrating Sonarr..."
K1_SONARR="/home/crussell/.local/share/containers/storage/volumes/sonarr-config/_data"
K3_SONARR="/var/lib/sonarr/.config/NzbDrone"

# On k1, the volume _data IS the config dir. On k3, data goes to /var/lib/sonarr/.config/NzbDrone
rsync -az --exclude='asp/' -e "ssh $SSH_OPTS" "$K1:$K1_SONARR/" "$K3_SONARR/"

# Fix UpdateMechanism: Docker -> External (NixOS manages updates)
sed -i 's|<UpdateMechanism>Docker</UpdateMechanism>|<UpdateMechanism>External</UpdateMechanism>|g' \
  "$K3_SONARR/config.xml"

chown -R sonarr:media /var/lib/sonarr

# ── Radarr ──────────────────────────────────────────────────────
echo "==> Migrating Radarr..."
K1_RADARR="/home/crussell/.local/share/containers/storage/volumes/radarr-config/_data"
K3_RADARR="/var/lib/radarr/.config/Radarr"

rsync -az --exclude='asp/' -e "ssh $SSH_OPTS" "$K1:$K1_RADARR/" "$K3_RADARR/"

sed -i 's|<UpdateMechanism>Docker</UpdateMechanism>|<UpdateMechanism>External</UpdateMechanism>|g' \
  "$K3_RADARR/config.xml"

chown -R radarr:media /var/lib/radarr

# ── Prowlarr ────────────────────────────────────────────────────
echo "==> Migrating Prowlarr..."
K1_PROWLARR="/home/crussell/.local/share/containers/storage/volumes/prowlarr-config/_data"
K3_PROWLARR="/var/lib/prowlarr"

rsync -az --exclude='asp/' -e "ssh $SSH_OPTS" "$K1:$K1_PROWLARR/" "$K3_PROWLARR/"

sed -i 's|<UpdateMechanism>Docker</UpdateMechanism>|<UpdateMechanism>External</UpdateMechanism>|g' \
  "$K3_PROWLARR/config.xml"

chown -R prowlarr:media /var/lib/prowlarr

# ── Jellyseerr ──────────────────────────────────────────────────
echo "==> Migrating Jellyseerr..."
K1_JSEERR="/home/crussell/.local/share/containers/storage/volumes/jellyseerr-config/_data"
K3_JSEERR="/var/lib/jellyseerr/config"

rsync -az -e "ssh $SSH_OPTS" "$K1:$K1_JSEERR/" "$K3_JSEERR/"

# Fix hostnames: container names -> localhost
# Also fix media paths
sed -i \
  -e 's|"ip": "jellyfin"|"ip": "127.0.0.1"|g' \
  -e 's|"hostname": "radarr"|"hostname": "127.0.0.1"|g' \
  -e 's|"hostname": "sonarr"|"hostname": "127.0.0.1"|g' \
  -e 's|"activeDirectory": "/media/|"activeDirectory": "/mnt/media/|g' \
  "$K3_JSEERR/settings.json"

chown -R jellyseerr:media /var/lib/jellyseerr

# ── qBittorrent ─────────────────────────────────────────────────
echo "==> Migrating qBittorrent..."
K1_QBT="/home/crussell/.config/qbittorrent"
K3_QBT="/var/lib/qBittorrent"

rsync -az --exclude='logs/' --exclude='.ash_history' --exclude='lockfile' --exclude='ipc-socket' -e "ssh $SSH_OPTS" "$K1:$K1_QBT/" "$K3_QBT/"

# Fix paths in qBittorrent config: /media -> /mnt/media, /config -> profile dir, /downloads -> /mnt/media/downloads
sed -i \
  -e 's|/media/|/mnt/media/|g' \
  -e 's|/downloads/|/mnt/media/downloads/|g' \
  -e 's|/config/qBittorrent/logs|/var/lib/qBittorrent/qBittorrent/logs|g' \
  "$K3_QBT/qBittorrent/qBittorrent.conf"

# Also fix paths in fastresume files (active torrents)
find "$K3_QBT/qBittorrent/BT_backup" -name '*.fastresume' -exec \
  sed -i 's|/media/|/mnt/media/|g; s|/downloads/|/mnt/media/downloads/|g' {} +

chown -R qbittorrent:media /var/lib/qBittorrent

# ── Start services ──────────────────────────────────────────────
echo "==> Starting all media services..."
systemctl start prowlarr sonarr radarr qbittorrent jellyfin jellyseerr

echo ""
echo "==> Migration complete! Checking service status..."
sleep 3
systemctl is-active jellyfin sonarr radarr prowlarr jellyseerr qbittorrent

echo ""
echo "==> Done. Verify each service:"
echo "    Jellyfin:     http://192.168.20.26:8096"
echo "    Sonarr:       http://192.168.20.26:8989"
echo "    Radarr:       http://192.168.20.26:7878"
echo "    Prowlarr:     http://192.168.20.26:9696"
echo "    Jellyseerr:   http://192.168.20.26:5055"
echo "    qBittorrent:  http://192.168.20.26:8080"
echo ""
echo "NOTE: You may need to re-link services in each app's settings"
echo "      if the API keys didn't carry over correctly."

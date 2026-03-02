#!/usr/bin/env bash
set -euo pipefail

echo "=== Creating /srv directory structure ==="

sudo mkdir -p /srv/{linkding,papra,ntfy,peekaping,audiobookshelf,adguardhome,searxng,karakeep,immich}/
sudo mkdir -p /srv/audiobookshelf/{audiobooks,config,metadata,podcasts}
sudo mkdir -p /srv/adguardhome/{work,conf}
sudo mkdir -p /srv/karakeep/{data,meilisearch}
sudo mkdir -p /srv/searxng/valkey
sudo mkdir -p /srv/immich/postgres

sudo chown -R $(id -u):$(id -g) /srv/

echo "=== Setting up NFS mount for photos ==="

sudo mkdir -p /mnt/nas/photos

if ! grep -q "/mnt/nas/photos" /etc/fstab; then
    echo "Adding NFS mount to /etc/fstab..."
    echo "192.168.20.31:/mnt/tank/photos /mnt/nas/photos nfs4 rw,soft,intr,timeo=30,retrans=3,_netdev 0 0" | sudo tee -a /etc/fstab
fi

sudo mount /mnt/nas/photos || echo "Mount may already exist or network not ready"

echo "=== Copying quadlet files ==="

mkdir -p ~/.config/containers/systemd/pods/{searxng,karakeep,immich}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for f in "$SCRIPT_DIR"/containers/*.container; do
    [ -f "$f" ] && cp "$f" ~/.config/containers/systemd/
done

cp "$SCRIPT_DIR"/pods/searxng/* ~/.config/containers/systemd/pods/searxng/
cp "$SCRIPT_DIR"/pods/karakeep/* ~/.config/containers/systemd/pods/karakeep/
cp "$SCRIPT_DIR"/pods/immich/* ~/.config/containers/systemd/pods/immich/

cp "$SCRIPT_DIR"/config/immich-postgresql.conf /srv/immich/postgresql.conf
cp "$SCRIPT_DIR"/config/searxng-settings.yml /srv/searxng/settings.yml

echo "=== Enabling lingering for user services ==="
sudo loginctl enable-linger $(whoami)

echo "=== Reloading systemd ==="
systemctl --user daemon-reload

echo ""
echo "=== Setup complete! ==="
echo ""
echo "Before starting services, migrate data from old nodes."
echo "See migrate-data.sh for migration script."
echo ""
echo "After migration, start services:"
echo "  systemctl --user enable --now linkding papra ntfy peekaping audiobookshelf adguardhome"
echo "  systemctl --user enable --now searxng karakeep immich"

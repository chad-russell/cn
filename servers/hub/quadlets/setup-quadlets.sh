#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Creating /srv directory structure ==="

sudo mkdir -p /srv/{linkding,papra,ntfy,peekaping,audiobookshelf,adguardhome,searxng,karakeep,immich,beszel,mastra}/
sudo mkdir -p /srv/audiobookshelf/{audiobooks,config,metadata,podcasts}
sudo mkdir -p /srv/adguardhome/{work,conf}
sudo mkdir -p /srv/karakeep/{data,meilisearch}
sudo mkdir -p /srv/searxng/valkey
sudo mkdir -p /srv/immich/postgres
sudo mkdir -p /srv/beszel
sudo mkdir -p /srv/mastra/data

sudo chown -R $(id -u):$(id -g) /srv/

echo "=== Setting up NFS mount for photos ==="

sudo mkdir -p /mnt/nas/photos

if ! grep -q "/mnt/nas/photos" /etc/fstab; then
    echo "Adding NFS mount to /etc/fstab..."
    echo "192.168.20.31:/mnt/tank/photos /mnt/nas/photos nfs4 rw,soft,intr,timeo=30,retrans=3,_netdev 0 0" | sudo tee -a /etc/fstab
fi

sudo mount /mnt/nas/photos || echo "Mount may already exist or network not ready"

echo "=== Decrypting secrets ==="

AGE_KEY="${HOME}/.config/age/key.txt"
SECRETS_DIR="${SCRIPT_DIR}/secrets"

if [[ ! -f "$AGE_KEY" ]]; then
    echo "ERROR: Age key not found at $AGE_KEY"
    echo "Please create an age key first or copy your existing key to that location."
    exit 1
fi

if ! command -v age &>/dev/null; then
    echo "ERROR: age command not found. Please install age:"
    echo "  https://github.com/FiloSottile/age#installation"
    exit 1
fi

age -d -i "$AGE_KEY" "$SECRETS_DIR/immich.env.age" > /srv/immich/secrets.env
age -d -i "$AGE_KEY" "$SECRETS_DIR/karakeep.env.age" > /srv/karakeep/secrets.env
age -d -i "$AGE_KEY" "$SECRETS_DIR/beszel-hub.env.age" > /srv/beszel/secrets.env
age -d -i "$AGE_KEY" "$SECRETS_DIR/searxng-settings.yml.age" > /srv/searxng/settings.yml
age -d -i "$AGE_KEY" "$SECRETS_DIR/peekaping.env.age" > /srv/peekaping/secrets.env

chmod 600 /srv/immich/secrets.env
chmod 600 /srv/karakeep/secrets.env
chmod 600 /srv/beszel/secrets.env
chmod 600 /srv/peekaping/secrets.env

echo "=== Copying quadlet files ==="

mkdir -p ~/.config/containers/systemd/pods/{searxng,karakeep,immich}

for f in "$SCRIPT_DIR"/containers/*.container; do
    [ -f "$f" ] && cp "$f" ~/.config/containers/systemd/
done

cp "$SCRIPT_DIR"/pods/searxng/* ~/.config/containers/systemd/pods/searxng/
cp "$SCRIPT_DIR"/pods/karakeep/* ~/.config/containers/systemd/pods/karakeep/
cp "$SCRIPT_DIR"/pods/immich/* ~/.config/containers/systemd/pods/immich/

cp "$SCRIPT_DIR"/config/immich-postgresql.conf /srv/immich/postgresql.conf

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

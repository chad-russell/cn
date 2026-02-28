#!/usr/bin/env bash
set -euo pipefail

# Migration script - run AFTER stopping swarm stacks on old nodes
# Old nodes: k2=192.168.20.62, k3=192.168.20.63, k4=192.168.20.64

SSH_KEY="$HOME/.ssh/id_ed25519"
SSH_OPTS="-i $SSH_KEY -o IdentitiesOnly=yes -o ConnectTimeout=10"

echo "=== This script should be run AFTER stopping all swarm stacks ==="
echo "On k2, run: docker stack rm linkding papra ntfy peekaping audiobookshelf searxng karakeep immich dozzle"
echo ""
read -p "Have you stopped all swarm stacks? (y/N) " confirm
if [[ "${confirm,,}" != "y" ]]; then
    echo "Aborting. Stop swarm stacks first."
    exit 1
fi

echo ""
echo "=== Extracting Docker named volumes from k2 ==="

ssh $SSH_OPTS crussell@192.168.20.62 << 'EOF'
mkdir -p /home/crussell/volume-backups

# Extract named volumes
for vol in linkding-data papra-data ntfy-data peekaping-data adguardhome-work adguardhome-conf searxng-valkey-data; do
    echo "Extracting $vol..."
    docker run --rm -v $vol:/data -v /home/crussell/volume-backups:/backup alpine tar czf /backup/$vol.tar.gz -C /data . 2>/dev/null || echo "Volume $vol not found or empty"
done
EOF

echo ""
echo "=== Syncing bind mount data from k2 ==="

rsync -avz --progress -e "ssh $SSH_OPTS" \
    crussell@192.168.20.62:/mnt/swarm-data/audiobookshelf/ \
    /srv/audiobookshelf/

rsync -avz --progress -e "ssh $SSH_OPTS" \
    crussell@192.168.20.62:/mnt/swarm-data/karakeep/ \
    /srv/karakeep/data/

rsync -avz --progress -e "ssh $SSH_OPTS" \
    crussell@192.168.20.62:/mnt/swarm-data/karakeep-meilisearch/ \
    /srv/karakeep/meilisearch/

rsync -avz --progress -e "ssh $SSH_OPTS" \
    crussell@192.168.20.62:/mnt/swarm-data/immich/postgres-data/ \
    /srv/immich/postgres/

echo ""
echo "=== Copying volume backups from k2 ==="

rsync -avz --progress -e "ssh $SSH_OPTS" \
    crussell@192.168.20.62:/home/crussell/volume-backups/ \
    /tmp/volume-backups/

echo ""
echo "=== Extracting volume tarballs ==="

for f in /tmp/volume-backups/*.tar.gz; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .tar.gz)
    echo "Extracting $name..."
    
    case $name in
        linkding-data) dest=/srv/linkding/data ;;
        papra-data) dest=/srv/papra/data ;;
        ntfy-data) dest=/srv/ntfy/cache ;;
        peekaping-data) dest=/srv/peekaping/data ;;
        adguardhome-work) dest=/srv/adguardhome/work ;;
        adguardhome-conf) dest=/srv/adguardhome/conf ;;
        searxng-valkey-data) dest=/srv/searxng/valkey ;;
        *) echo "Unknown volume: $name"; continue ;;
    esac
    
    mkdir -p "$dest"
    tar xzf "$f" -C "$dest"
done

echo ""
echo "=== Setting permissions ==="
sudo chown -R $(id -u):$(id -g) /srv/

echo ""
echo "=== Migration complete! ==="
echo ""
echo "Verify data looks correct, then start services:"
echo "  systemctl --user start linkding papra ntfy peekaping audiobookshelf adguardhome"
echo "  systemctl --user start searxng karakeep immich"

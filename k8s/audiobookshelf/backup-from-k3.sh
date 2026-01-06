#!/bin/bash
# Run this script on k3 (192.168.20.63) to backup audiobookshelf volumes

set -e

echo "Stopping audiobookshelf..."
cd ~/cn/k3/docker/audiobookshelf
docker-compose down

echo "Creating backups in /tmp..."
cd /tmp

echo "Backing up audiobooks volume..."
docker run --rm -v audiobookshelf-audiobooks:/data -v /tmp:/backup busybox tar czf /backup/audiobookshelf-audiobooks.tar.gz -C /data .

echo "Backing up podcasts volume..."
docker run --rm -v audiobookshelf-podcasts:/data -v /tmp:/backup busybox tar czf /backup/audiobookshelf-podcasts.tar.gz -C /data .

echo "Backing up config volume..."
docker run --rm -v audiobookshelf-config:/data -v /tmp:/backup busybox tar czf /backup/audiobookshelf-config.tar.gz -C /data .

echo "Backing up metadata volume..."
docker run --rm -v audiobookshelf-metadata:/data -v /tmp:/backup busybox tar czf /backup/audiobookshelf-metadata.tar.gz -C /data .

echo ""
echo "Backups complete! Files created in /tmp:"
ls -lh /tmp/audiobookshelf-*.tar.gz
echo ""
echo "To copy to your local machine, run:"
echo "scp crussell@192.168.20.63:/tmp/audiobookshelf-*.tar.gz /tmp/"








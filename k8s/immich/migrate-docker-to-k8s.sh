#!/bin/bash
# Database migration script for Immich
set -e

echo "=== Immich Database Migration ==="
echo "Step 1: Creating backup from Docker instance..."

# Create backup from Docker
docker exec -t immich_postgres pg_dump -U postgres -d immich -Fc > /mnt/immich/backups/k8s-migration/immich-db-backup.sql

echo "Backup created: /mnt/immich/backups/k8s-migration/immich-db-backup.sql"
ls -lh /mnt/immich/backups/k8s-migration/immich-db-backup.sql

echo ""
echo "Step 2: Stopping Docker Immich..."
docker compose stop

echo ""
echo "Step 3: Migration ready!"
echo "Now run the restore on Kubernetes:"
echo "kubectl exec -n immich db-restore-helper -- pg_restore -h immich-database-rw -U postgres -d immich --clean --if-exists /tmp/backup.sql"

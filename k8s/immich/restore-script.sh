#!/bin/bash
# Restore Immich database from Docker backup
set -e

echo "=== Starting Immich Database Migration ==="

# The backup is located at /mnt/immich/backups/k8s-migration/immich-db-backup.sql
# This is accessible from the database pod via the NFS mount

# First, let's check the backup file
BACKUP_FILE="/mnt/immich/backups/k8s-migration/immich-db-backup.sql"

echo "Step 1: Checking backup file..."
if [ ! -f "$BACKUP_FILE" ]; then
    echo "ERROR: Backup file not found at $BACKUP_FILE"
    exit 1
fi

echo "Backup file found: $(ls -lh $BACKUP_FILE)"

# The backup is a custom format dump, we need to use pg_restore
# But first we need to terminate any existing connections and drop the database
echo ""
echo "Step 2: Preparing database for restore..."

# Connect as postgres superuser and prepare database
psql -U postgres -d postgres << EOF
-- Terminate existing connections
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'immich' AND pid <> pg_backend_pid();

-- Drop and recreate database
DROP DATABASE IF EXISTS immich;
CREATE DATABASE immich OWNER immich;

-- Connect to new database and create extensions
\c immich
CREATE EXTENSION IF NOT EXISTS vchord CASCADE;
CREATE EXTENSION IF NOT EXISTS earthdistance CASCADE;
EOF

echo ""
echo "Step 3: Restoring database from backup..."
pg_restore -U postgres -d immich --clean --if-exists "$BACKUP_FILE"

echo ""
echo "Step 4: Verifying restore..."
psql -U immich -d immich -c "SELECT COUNT(*) FROM users;"

echo ""
echo "=== Migration Complete ==="
echo "Database restored successfully!"

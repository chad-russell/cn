#!/usr/bin/env bash
# One-shot first-time setup for the restic backup:
#   1. build the restic image           (image/build.sh)
#   2. seed /etc/restic-backup creds     (seed.sh)
#   3. ensure the S3 repo is initialized (one-shot init container)
#   4. install Quadlets + timers         (install.sh)
#
# Idempotent — safe to re-run. The image build pulls docker.io/restic/restic on
# first run.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="s3:https://s3.us-east-2.amazonaws.com/crussell-restic-backups/think"

echo "==> [1/4] Building image..."
"$SELF_DIR/image/build.sh"

echo
echo "==> [2/4] Seeding /etc/restic-backup..."
"$SELF_DIR/seed.sh"

echo
echo "==> [3/4] Ensuring S3 repo is initialized..."
# Idempotent: if snapshots list succeeds the repo exists; otherwise init it.
sudo podman run --rm \
  -v /etc/restic-backup:/secrets:ro \
  -v restic-backup-cache:/root/.cache/restic \
  --env-file /etc/restic-backup/s3.env \
  -e "RESTIC_REPOSITORY=$REPO_URL" \
  -e RESTIC_PASSWORD_FILE=/secrets/password \
  localhost/restic-backup:think \
  sh -c 'restic snapshots >/dev/null 2>&1 && echo "repo exists, skipping init" || restic init'

echo
echo "==> [4/4] Installing Quadlets + timers..."
"$SELF_DIR/install.sh"

echo
echo "==> Done. First backup runs on the daily timer, or run now:"
echo "    sudo systemctl start restic-backup.service"

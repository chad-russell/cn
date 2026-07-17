#!/usr/bin/env bash
# Ad-hoc restic against the think S3 repo, using the seeded creds + cache.
# Mirrors the backup/check containers' env. Calls sudo internally (rootful
# podman; secrets are root-only).
#
# Usage:
#   hosts/thinkpad/backup/restic.sh snapshots
#   hosts/thinkpad/backup/restic.sh ls latest
#   hosts/thinkpad/backup/restic.sh stats --mode raw-data
#   hosts/thinkpad/backup/restic.sh forget <snapshot-id> --prune
#
# (For `restore`, which writes to the host, bind-mount an output dir into the
# container yourself — see backup/README.md.)
set -euo pipefail

sudo podman run --rm \
  -v /etc/restic-backup:/secrets:ro \
  -v restic-backup-cache:/root/.cache/restic \
  --env-file /etc/restic-backup/s3.env \
  -e RESTIC_REPOSITORY=s3:https://s3.us-east-2.amazonaws.com/crussell-restic-backups/think \
  -e RESTIC_PASSWORD_FILE=/secrets/password \
  localhost/restic-backup:think restic "$@"

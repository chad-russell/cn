#!/usr/bin/env bash
set -euo pipefail

export XDG_CACHE_HOME="/var/cache/restic-s3"
mkdir -p "$XDG_CACHE_HOME"

LOCAL_REPO="/var/mnt/tank/backups/hub-restic"
NFS_MOUNT="/var/mnt/tank/backups"
S3_REPO="s3:s3.us-east-2.amazonaws.com/crussell-hub-restic-backup-39bj28x7"
PASSWORD_FILE="/etc/restic/password"
AWS_CREDS_DIR="/etc/restic/aws"
NTFY_URL="https://ntfy.internal.crussell.io"
NTFY_TOPIC="backups"

send_notification() {
    local priority="$1"
    local title="$2"
    local message="$3"
    curl -s -X POST "$NTFY_URL/$NTFY_TOPIC" \
        -H "Title: $title" \
        -H "Priority: $priority" \
        -d "$message" >/dev/null 2>&1 || true
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

load_aws_creds() {
    if [[ ! -f "$AWS_CREDS_DIR/access_key" ]] || [[ ! -f "$AWS_CREDS_DIR/secret_key" ]]; then
        log "ERROR: AWS credentials not found at $AWS_CREDS_DIR"
        send_notification "urgent" "S3 Copy Failed" "AWS credentials missing"
        exit 1
    fi
    export AWS_ACCESS_KEY_ID=$(cat "$AWS_CREDS_DIR/access_key")
    export AWS_SECRET_ACCESS_KEY=$(cat "$AWS_CREDS_DIR/secret_key")
}

ensure_mount() {
    if ! mountpoint -q "$NFS_MOUNT" 2>/dev/null; then
        log "Triggering automount..."
        ls "$NFS_MOUNT" >/dev/null 2>&1 || true
        sleep 2
        if ! mountpoint -q "$NFS_MOUNT" 2>/dev/null; then
            log "ERROR: NFS mount not accessible at $NFS_MOUNT"
            send_notification "urgent" "S3 Copy Failed" "NFS mount not accessible"
            exit 1
        fi
    fi

    if [[ ! -d "$LOCAL_REPO" ]]; then
        log "ERROR: Local repository not found at $LOCAL_REPO"
        send_notification "urgent" "S3 Copy Failed" "Local repository not found"
        exit 1
    fi
}

run_copy() {
    log "Starting restic copy to S3..."

    restic copy \
        --from-repo "$LOCAL_REPO" \
        --repo "$S3_REPO" \
        --password-file "$PASSWORD_FILE" \
        --from-password-file "$PASSWORD_FILE"

    log "Copy complete"
}

main() {
    log "=== Starting S3 copy run ==="

    if [[ ! -f "$PASSWORD_FILE" ]]; then
        log "ERROR: Password file not found at $PASSWORD_FILE"
        send_notification "urgent" "S3 Copy Failed" "Password file missing"
        exit 1
    fi

    ensure_mount
    load_aws_creds
    run_copy

    local s3_stats
    s3_stats=$(restic stats --repo "$S3_REPO" --password-file "$PASSWORD_FILE" 2>/dev/null | head -5)

    send_notification "default" "S3 Copy Complete" "Weekly S3 backup copy finished\n\n$s3_stats"

    log "=== S3 copy run finished ==="
}

main "$@"

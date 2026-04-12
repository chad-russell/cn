#!/usr/bin/env bash
set -euo pipefail

export XDG_CACHE_HOME="/var/cache/restic"
mkdir -p "$XDG_CACHE_HOME"

REPO="/var/mnt/tank/backups/hub-restic"
PASSWORD_FILE="/etc/restic/password"
EXCLUDE_FILE="/etc/restic/excludes"
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

dump_sqlite_dbs() {
    log "Dumping SQLite databases..."
    local dump_dir="/var/tmp/restic-sqlite-dumps"
    rm -rf "$dump_dir"
    mkdir -p "$dump_dir"
    
    local sqlite_img="docker.io/alpine:latest"
    
    if [[ -f "/srv/linkding/data/db.sqlite3" ]]; then
        podman run --rm --security-opt label=disable \
            -v /srv/linkding/data:/data:ro "$sqlite_img" \
            sh -c "apk add --no-cache sqlite >/dev/null 2>&1 && sqlite3 /data/db.sqlite3 .dump" \
            > "$dump_dir/linkding.sql"
        log "  Dumped linkding database"
    fi
    
    if [[ -f "/srv/peekaping/data/peekaping.db" ]]; then
        podman run --rm --security-opt label=disable \
            -v /srv/peekaping/data:/data:ro "$sqlite_img" \
            sh -c "apk add --no-cache sqlite >/dev/null 2>&1 && sqlite3 /data/peekaping.db .dump" \
            > "$dump_dir/peekaping.sql"
        log "  Dumped peekaping database"
    fi
    
    if [[ -f "/srv/beszel/data/beszel.db" ]]; then
        podman run --rm --security-opt label=disable \
            -v /srv/beszel/data:/data:ro "$sqlite_img" \
            sh -c "apk add --no-cache sqlite >/dev/null 2>&1 && sqlite3 /data/beszel.db .dump" \
            > "$dump_dir/beszel.sql"
        log "  Dumped beszel database"
    fi
    
    if [[ -f "/srv/open-webui/data/webui.db" ]]; then
        podman run --rm --security-opt label=disable \
            -v /srv/open-webui/data:/data:ro "$sqlite_img" \
            sh -c "apk add --no-cache sqlite >/dev/null 2>&1 && sqlite3 /data/webui.db .dump" \
            > "$dump_dir/open-webui.sql"
        log "  Dumped open-webui database"
    fi

}

backup_podman_volumes() {
    log "Exporting named Podman volumes..."
    local vol_dir="/var/tmp/restic-volume-exports"
    rm -rf "$vol_dir"
    mkdir -p "$vol_dir"
    
    if podman volume exists caddy_data 2>/dev/null; then
        podman volume export caddy_data -o "$vol_dir/caddy_data.tar"
        log "  Exported caddy_data"
    fi
    
    if podman volume exists caddy_config 2>/dev/null; then
        podman volume export caddy_config -o "$vol_dir/caddy_config.tar"
        log "  Exported caddy_config"
    fi
}

run_backup() {
    log "Starting restic backup..."
    
    restic backup \
        --repo "$REPO" \
        --password-file "$PASSWORD_FILE" \
        --exclude-file "$EXCLUDE_FILE" \
        --tag "hub-$(date '+%Y-%m-%d')" \
        /srv/linkding/data \
        /srv/papra/data \
        /srv/peekaping/data \
        /srv/audiobookshelf/config \
        /srv/audiobookshelf/metadata \
        /srv/adguardhome/conf \
        /srv/beszel/data \
        /srv/open-webui/data \
        /var/tmp/restic-sqlite-dumps \
        /var/tmp/restic-volume-exports \
        /etc/restic \
        /home/crussell/.config/containers/systemd \
        /home/crussell/Code/cn/nebula/pki
    
    log "Backup complete"
}

run_prune() {
    log "Pruning old backups..."
    restic forget \
        --repo "$REPO" \
        --password-file "$PASSWORD_FILE" \
        --keep-daily 7 \
        --keep-weekly 4 \
        --keep-monthly 12 \
        --prune
    
    log "Prune complete"
}

cleanup() {
    rm -rf /var/tmp/restic-sqlite-dumps /var/tmp/restic-volume-exports
}

main() {
    log "=== Starting backup run ==="
    
    if [[ ! -f "$PASSWORD_FILE" ]]; then
        log "ERROR: Password file not found at $PASSWORD_FILE"
        send_notification "urgent" "Backup Failed" "Password file missing"
        exit 1
    fi
    
    if ! mountpoint -q "$REPO" 2>/dev/null && [[ ! -d "$REPO" ]]; then
        log "ERROR: Backup repository not accessible at $REPO"
        send_notification "urgent" "Backup Failed" "Repository not accessible"
        exit 1
    fi
    
    trap cleanup EXIT
    
    dump_sqlite_dbs || true
    backup_podman_volumes || true
    run_backup
    run_prune
    
    local stats
    stats=$(restic stats --repo "$REPO" --password-file "$PASSWORD_FILE" 2>/dev/null | head -5)
    
    send_notification "default" "Backup Complete" "Hub backup finished successfully\n\n$stats"
    
    log "=== Backup run finished ==="
}

main "$@"

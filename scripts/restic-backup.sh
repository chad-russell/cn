#!/bin/bash
set -e

CONFIG="/etc/restic-backup.json"
PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-/etc/restic-password}"
REPOSITORY="${RESTIC_REPOSITORY:-/mnt/backups/restic}"
NTFY_URL="${NTFY_URL:-}"
LOGTAG="restic-backup"

log() {
    local level="$1"
    shift
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $@" | systemd-cat -t "$LOGTAG" -p "$level"
}

notify_failure() {
    local service="$1"
    local error="$2"
    
    if [ -n "$NTFY_URL" ]; then
        curl -s -X POST "$NTFY_URL" \
            -H "Title: ❌ Backup Failed: $service" \
            -H "Priority: urgent" \
            -d "Backup failed for service: $service

Error: $error
Node: $(hostname)
Time: $(date)" || log warning "Failed to send NTFY notification"
    fi
}

check_nfs() {
    if ! mountpoint -q "/mnt/backups"; then
        log error "NFS not mounted at /mnt/backups"
        notify_failure "nfs-mount" "NFS mount check failed"
        return 1
    fi
    log info "NFS mount verified"
    return 0
}

init_repo() {
    if [ ! -d "$REPOSITORY/config" ]; then
        log info "Initializing restic repository..."
        if restic init 2>&1 | systemd-cat -t "$LOGTAG" -p info; then
            log info "Repository initialized"
            return 0
        else
            log error "Failed to initialize repository"
            notify_failure "repo-init" "Repository initialization failed"
            return 1
        fi
    else
        log info "Repository exists, checking health..."
        if ! restic check --read-data 2>&1 | systemd-cat -t "$LOGTAG" -p info; then
            log warning "Repository check failed, attempting repair"
            restic repair 2>&1 | systemd-cat -t "$LOGTAG" -p info
        else
            log info "Repository healthy"
        fi
        return 0
    fi
}

find_container_id() {
    local service_name="$1"
    docker ps -q --filter "name=$service_name" | head -1
}

backup_service() {
    local service_name="$1"
    local backup_type="$2"
    local targets="$3"
    local pre_stop="$4"
    local post_start="$5"
    local excludes="$6"
    
    log info "Starting backup: $service_name"
    
    local container_id=""
    if [ -n "$pre_stop" ]; then
        container_id=$(find_container_id "$pre_stop")
        if [ -z "$container_id" ]; then
            log warning "Container '$pre_stop' not found, skipping stop"
        else
            log info "Stopping: $pre_stop ($container_id)"
            if ! docker stop "$container_id" 2>&1 | systemd-cat -t "$LOGTAG" -p info; then
                log warning "Failed to stop container $pre_stop"
            fi
        fi
    fi
    
    local backup_success=0
    local backup_error=""
    local exclude_args=""
    
    if [ -n "$excludes" ]; then
        for pattern in $excludes; do
            exclude_args="$exclude_args --exclude $pattern"
        done
    fi
    
    if [ "$backup_type" = "volume" ]; then
        for vol in $targets; do
            [ -z "$vol" ] && continue
            log info "Backing up volume: $vol"
            
            if docker run --rm -v "$vol:/data:ro" alpine:latest \
                restic backup /data $exclude_args --tag "$service_name" --tag "volume:$vol" 2>&1 | systemd-cat -t "$LOGTAG" -p info; then
                log info "Volume $vol backed up successfully"
            else
                log error "Failed to backup volume $vol"
                backup_success=1
                backup_error="Volume backup failed: $vol"
            fi
        done
    elif [ "$backup_type" = "bind" ]; then
        for path in $targets; do
            [ -z "$path" ] && continue
            [ ! -d "$path" ] && continue
            log info "Backing up path: $path"
            
            if restic backup "$path" $exclude_args --tag "$service_name" --tag "path:$(basename $path)" 2>&1 | systemd-cat -t "$LOGTAG" -p info; then
                log info "Path $path backed up successfully"
            else
                log error "Failed to backup path $path"
                backup_success=1
                backup_error="Path backup failed: $path"
            fi
        done
    fi
    
    if [ -n "$post_start" ]; then
        container_id=$(find_container_id "$post_start")
        if [ -z "$container_id" ]; then
            log warning "Container '$post_start' not found, skipping start"
        else
            log info "Starting: $post_start ($container_id)"
            if ! docker start "$container_id" 2>&1 | systemd-cat -t "$LOGTAG" -p info; then
                log warning "Failed to start container $post_start"
            fi
        fi
    fi
    
    if [ "$backup_success" -eq 1 ]; then
        notify_failure "$service_name" "$backup_error"
        return 1
    fi
    
    validate_backup "$service_name"
    
    log info "Completed backup: $service_name"
    return 0
}

validate_backup() {
    local service_name="$1"
    log info "Validating backup for $service_name..."
    
    local snapshot_count
    snapshot_count=$(restic snapshots --tag "$service_name" --json 2>/dev/null | jq '. | length' || echo "0")
    
    if [ "$snapshot_count" -eq 0 ]; then
        log error "Validation failed: No snapshots found for $service_name"
        notify_failure "$service_name" "Validation failed: No snapshots found"
        return 1
    fi
    
    log info "Validation successful: $service_name (total snapshots: $snapshot_count)"
    return 0
}

prune_backups() {
    log info "Pruning old backups..."
    
    if restic forget \
        --keep-hourly 24 \
        --keep-daily 7 \
        --keep-weekly 4 \
        --keep-monthly 3 \
        --keep-yearly 1 \
        --prune 2>/dev/null; then
        log info "Prune completed"
        return 0
    else
        log error "Prune failed"
        notify_failure "prune" "Backup pruning failed"
        return 1
    fi
}

main() {
    log info "Starting backup run"
    
    if ! check_nfs; then
        log error "Aborting due to NFS mount failure"
        exit 1
    fi
    
    if ! init_repo; then
        log error "Aborting due to repository initialization failure"
        exit 1
    fi
    
    if [ ! -f "$CONFIG" ]; then
        log error "Config file not found: $CONFIG"
        notify_failure "config" "Backup config file not found"
        exit 1
    fi
    
    local success_count=0
    local failed_count=0
    
    while read -r job; do
        service_name=$(echo "$job" | jq -r '.name')
        backup_type=$(echo "$job" | jq -r '.type // "volume"')
        targets=$(echo "$job" | jq -r '.targets[]? // empty' | tr '\n' ' ')
        pre_stop=$(echo "$job" | jq -r '.pre_stop // empty')
        post_start=$(echo "$job" | jq -r '.post_start // empty')
        excludes=$(echo "$job" | jq -r '.exclude[]? // empty' | tr '\n' ' ')
        
        if [ -z "$service_name" ]; then
            log warning "Skipping job with no name"
            continue
        fi
        
        if backup_service "$service_name" "$backup_type" "$targets" "$pre_stop" "$post_start" "$excludes"; then
            ((success_count++))
        else
            ((failed_count++))
        fi
    done < <(jq -c '.jobs[]' "$CONFIG")
    
    if [ "$success_count" -gt 0 ]; then
        prune_backups
    fi
    
    local total_jobs=$((success_count + failed_count))
    log info "Backup summary: $success_count/$total_jobs succeeded, $failed_count failed"
    
    if [ "$failed_count" -gt 0 ]; then
        notify_failure "summary" "$failed_count of $total_jobs backup jobs failed"
        exit 1
    fi
    
    log info "Backup run completed successfully"
}

main

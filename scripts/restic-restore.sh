#!/bin/bash
set -e

REPOSITORY="${RESTIC_REPOSITORY:-/mnt/backups/restic}"
PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-/etc/restic-password}"
CONFIG="/etc/restic-backup.json"

export RESTIC_PASSWORD_FILE="$PASSWORD_FILE"
export RESTIC_REPOSITORY="$REPOSITORY"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $@"
}

get_service_config() {
    local service="$1"
    jq -r ".jobs[] | select(.name == \"$service\")" "$CONFIG"
}

get_restore_target() {
    local service="$1"
    local config="$2"
    
    local backup_type
    local targets
    
    backup_type=$(echo "$config" | jq -r '.type // "volume"')
    targets=$(echo "$config" | jq -r '.targets[0] // empty')
    
    case "$service" in
        linkding)
            echo "/mnt/swarm-data/linkding"
            ;;
        karakeep)
            echo "/mnt/swarm-data/karakeep"
            ;;
        audiobookshelf)
            echo "/mnt/swarm-data/audiobookshelf"
            ;;
        caddy)
            echo "/home/crussell/caddy/Caddyfile"
            ;;
        *)
            if [ "$backup_type" = "volume" ]; then
                echo "volume:$targets"
            else
                echo "$targets"
            fi
            ;;
    esac
}

find_container_id() {
    local service_name="$1"
    docker ps -q --filter "name=$service_name" | head -1
}

list_snapshots() {
    local service="$1"
    
    echo ""
    echo "Available snapshots for '$service':"
    echo "----------------------------------------"
    
    restic snapshots --tag "$service" --compact --json | \
        jq -r '.[] | "\(.short_id)  \(.time)  \(.paths | join(\", \"))"' | \
        awk 'BEGIN {print "ID        Date                 Paths"; print "----------------------------------------"} {printf "%-10s %-20s %s\n", $1, $2, $3}'
    
    echo ""
}

stop_container() {
    local service="$1"
    local config="$2"
    
    local pre_stop
    pre_stop=$(echo "$config" | jq -r '.pre_stop // empty')
    
    if [ -n "$pre_stop" ]; then
        local container_id
        container_id=$(find_container_id "$pre_stop")
        
        if [ -n "$container_id" ]; then
            log "Stopping container: $pre_stop ($container_id)"
            docker stop "$container_id"
            echo "$container_id" > /tmp/restore_container_id
        else
            log "Warning: Container '$pre_stop' not found or already stopped"
        fi
    fi
}

start_container() {
    local service="$1"
    local config="$2"
    
    if [ -f /tmp/restore_container_id ]; then
        local container_id
        container_id=$(cat /tmp/restore_container_id)
        
        log "Starting container: $container_id"
        docker start "$container_id"
        rm /tmp/restore_container_id
    fi
    
    local post_start
    post_start=$(echo "$config" | jq -r '.post_start // empty')
    
    if [ -n "$post_start" ]; then
        local container_id
        container_id=$(find_container_id "$post_start")
        
        if [ -z "$container_id" ]; then
            log "Starting container: $post_start"
            docker start "$(docker ps -aq --filter "name=$post_start" | head -1)"
        fi
    fi
}

restore_snapshot() {
    local service="$1"
    local snapshot_id="$2"
    local config="$3"
    
    local target
    target=$(get_restore_target "$service" "$config")
    
    log "Restoring $service from snapshot: $snapshot_id"
    log "Target: $target"
    
    if [[ "$target" == volume:* ]]; then
        local vol_name
        vol_name="${target#volume:}"
        log "Restoring to Docker volume: $vol_name"
        
        docker run --rm -v "$vol_name:/target" alpine:latest \
            restic restore "$snapshot_id" --target /target
    else
        if [ ! -d "$target" ]; then
            log "Error: Target directory does not exist: $target"
            return 1
        fi
        
        log "Restoring to path: $target"
        restic restore "$snapshot_id" --target "$target"
    fi
    
    log "Restore completed"
}

main() {
    if [ $# -lt 1 ]; then
        echo "Usage: $0 <service-name> [snapshot-id]"
        echo ""
        echo "Examples:"
        echo "  $0 linkding                    # List snapshots for linkding"
        echo "  $0 linkding abc123            # Restore latest snapshot by prefix"
        echo ""
        echo "Available services:"
        jq -r '.jobs[].name' "$CONFIG" | sed 's/^/  - /'
        exit 1
    fi
    
    local service="$1"
    local snapshot_id="$2"
    
    if [ ! -f "$CONFIG" ]; then
        log "Error: Config file not found: $CONFIG"
        exit 1
    fi
    
    local config
    config=$(get_service_config "$service")
    
    if [ -z "$config" ]; then
        log "Error: Service '$service' not found in configuration"
        echo ""
        echo "Available services:"
        jq -r '.jobs[].name' "$CONFIG" | sed 's/^/  - /'
        exit 1
    fi
    
    if [ -z "$snapshot_id" ]; then
        list_snapshots "$service"
        
        echo ""
        read -p "Enter snapshot ID to restore (or Ctrl+C to cancel): " snapshot_id
        
        if [ -z "$snapshot_id" ]; then
            log "Restore cancelled"
            exit 0
        fi
    else
        local snapshot_info
        snapshot_info=$(restic snapshots --tag "$service" --json | jq -r ".[] | select(.short_id | startswith(\"$snapshot_id\")) | \(.short_id) \(.time) \(.paths | join(\", \"))" 2>/dev/null)
        
        if [ -z "$snapshot_info" ]; then
            log "Error: Snapshot '$snapshot_id' not found for service '$service'"
            exit 1
        fi
    fi
    
    local target
    target=$(get_restore_target "$service" "$config")
    
    echo ""
    echo "WARNING: This will restore the following data:"
    echo "  Service: $service"
    echo "  Snapshot: $snapshot_id"
    echo "  Target: $target"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        log "Restore cancelled"
        exit 0
    fi
    
    stop_container "$service" "$config"
    
    if restore_snapshot "$service" "$snapshot_id" "$config"; then
        log "Restore successful"
    else
        log "Restore failed"
        exit 1
    fi
    
    sleep 2
    start_container "$service" "$config"
    
    log "Restore completed and service restarted"
}

main "$@"

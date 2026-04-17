#!/usr/bin/env bash
set -euo pipefail

NTFY_URL="https://ntfy.internal.crussell.io"
NTFY_TOPIC="healthcheck"

DISK_THRESHOLD=90
LOAD_THRESHOLD=5
MEM_THRESHOLD=90

FAILURES=()
NOTIFIED=false

notify() {
    local priority="${1:-default}"
    local title="${2:-Healthcheck}"
    local message="$3"
    curl -s -X POST "$NTFY_URL/$NTFY_TOPIC" \
        -H "Title: $title" \
        -H "Priority: $priority" \
        -H "Tags: warning" \
        -d "$message" >/dev/null 2>&1 || true
    NOTIFIED=true
}

fail() {
    FAILURES+=("$1")
    echo "FAIL: $1"
}

ok() {
    echo "  OK: $1"
}

# --- Host reachability ---

HOSTS=(
    "media|192.168.20.61"
    "nas|192.168.20.31"
    "gateway|178.156.171.212"
)

echo "=== Host Reachability ==="
for entry in "${HOSTS[@]}"; do
    IFS='|' read -r name ip <<< "$entry"
    if ping -c 1 -W 3 "$ip" >/dev/null 2>&1; then
        ok "$name ($ip)"
    else
        fail "$name ($ip) is unreachable"
    fi
done

# --- HTTP service checks ---

SERVICES=(
    "linkding|http://127.0.0.1:30080"
    "papra|http://127.0.0.1:30083"
    "ntfy|http://127.0.0.1:30085/v1"
    "searxng|http://127.0.0.1:30084"
    "open-webui|http://127.0.0.1:30088"
    "adguard|http://127.0.0.1:30100"
    "immich|http://127.0.0.1:30093"
    "datenight|http://127.0.0.1:30790"
    "jellyfin|http://192.168.20.61:8096"
    "jellyseerr|http://192.168.20.61:5055"
    "radarr|http://192.168.20.61:7878"
    "sonarr|http://192.168.20.61:8989"
    "prowlarr|http://192.168.20.61:9696"
    "qbittorrent|http://192.168.20.61:8080"
)

echo ""
echo "=== Service Health ==="
for entry in "${SERVICES[@]}"; do
    IFS='|' read -r name url <<< "$entry"
    status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || echo "000")
    if [[ "$status" -ge 200 && "$status" -lt 400 ]] || [[ "$status" == "401" ]]; then
        ok "$name ($status)"
    else
        fail "$name returned HTTP $status ($url)"
    fi
done

# --- Resource checks (localhost) ---

echo ""
echo "=== Resource Usage ==="

while read -r mount pct; do
    pct="${pct%\%}"
    if [[ "$pct" -ge "$DISK_THRESHOLD" ]]; then
        fail "Disk $mount is ${pct}% full (threshold: ${DISK_THRESHOLD}%)"
    else
        ok "Disk $mount at ${pct}%"
    fi
done < <(df --output=target,pcent -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | tail -n +2 | grep -v -E '^\s*/\s')

load=$(awk '{print $1}' /proc/loadavg)
load_int=${load%%.*}
if [[ "$load_int" -ge "$LOAD_THRESHOLD" ]]; then
    fail "Load average is $load (threshold: ${LOAD_THRESHOLD})"
else
    ok "Load average: $load"
fi

mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
mem_avail=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
if [[ "$mem_total" -gt 0 ]]; then
    mem_used_pct=$(( 100 - (mem_avail * 100 / mem_total) ))
    if [[ "$mem_used_pct" -ge "$MEM_THRESHOLD" ]]; then
        fail "Memory usage is ${mem_used_pct}% (threshold: ${MEM_THRESHOLD}%)"
    else
        ok "Memory at ${mem_used_pct}%"
    fi
fi

# --- Summary ---

echo ""
if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo "=== FAILURES: ${#FAILURES[@]} ==="
    printf '%s\n' "${FAILURES[@]}"
    msg=$(printf '%s\n' "${FAILURES[@]}")
    notify "high" "Healthcheck: ${#FAILURES[@]} issue(s)" "$msg"
else
    echo "=== All checks passed ==="
fi

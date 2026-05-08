#!/usr/bin/env bash
# ── Homelab Infrastructure Monitor ─────────────────────────────────
#
# Collects metrics from Prometheus, logs via SSH, and uses pi (AI)
# to analyze the data and surface issues via ntfy.
#
# Usage: collect.sh [check|daily]
#   check  — 3-hourly critical check (alerts only if issues found)
#   daily  — comprehensive daily report (always sent)
#
# Runs as a systemd service on bees (production server).

set -euo pipefail

MODE="${1:-check}"

# ── Configuration ──────────────────────────────────────────────────
PROM_URL="http://localhost:9090"
NTFY_URL="http://localhost:8090"
NTFY_TOPIC="homelab-monitor"
PROMPT_FILE="/etc/homelab-monitor/system-prompt.md"

SSH_OPTS="-o IdentitiesOnly=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o BatchMode=yes"

# ── Time range based on mode ───────────────────────────────────────
if [ "$MODE" = "daily" ]; then
    HOURS=24
    RANGE="24h"
else
    HOURS=3
    RANGE="3h"
fi

DATA=$(mktemp /tmp/homelab-data-XXXXXX.md)
trap "rm -f $DATA" EXIT

log() { echo "[$(date +'%H:%M:%S')] $*" >&2; }

log "Starting homelab monitor (mode=$MODE, period=${HOURS}h)"

# ── Helper: Prometheus instant query → single value ────────────────
prom_val() {
    local query="$1"
    local raw
    raw=$(curl -sf "$PROM_URL/api/v1/query" --data-urlencode "query=$query" 2>/dev/null \
        | jq -r '.data.result[0].value[1] // empty' 2>/dev/null) || true
    if [ -z "$raw" ] || [ "$raw" = "NaN" ] || [ "$raw" = "+Inf" ] || [ "$raw" = "-Inf" ]; then
        echo "N/A"
    else
        printf "%.1f" "$raw" 2>/dev/null || echo "$raw"
    fi
}

# ── Helper: Prometheus instant query → multi-value (per label) ─────
prom_labels() {
    local query="$1"
    local label="$2"
    curl -sf "$PROM_URL/api/v1/query" --data-urlencode "query=$query" 2>/dev/null \
        | jq -r --arg lbl "$label" '.data.result[] | "  \(.metric[$lbl]): \(.value[1])"' 2>/dev/null || echo "  N/A"
}

# ── Helper: SSH with error handling ────────────────────────────────
ssh_cmd() {
    local user_host="$1"
    shift
    ssh $SSH_OPTS "$user_host" "$@" 2>/dev/null || echo "(SSH failed)"
}

# ── Helper: check if host is reachable ─────────────────────────────
ssh_reachable() {
    ssh $SSH_OPTS "$1" "echo ok" >/dev/null 2>&1
}

# ══════════════════════════════════════════════════════════════════════
# DATA COLLECTION
# ══════════════════════════════════════════════════════════════════════

{
    echo "# Homelab Infrastructure Data"
    echo "# Mode: $MODE | Period: last ${HOURS}h | Generated: $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
    echo ""
    echo "## Machine Overview"
    echo "- bees (10.10.0.6): Production — Caddy, Jellyfin, Immich, ntfy, SearXNG, linkding, papra, open-webui, media services"
    echo "- bee (10.10.0.12): Dev — Gloo stack, Nebula lighthouse"
    echo "- think (10.10.0.10): Laptop — may be offline"
    echo "- nas (10.10.0.3): TrueNAS — NFS storage"
    echo "- gateway (10.10.0.2): Hetzner VPS — nginx proxy, Nebula relay"
    echo ""

    # ── Prometheus metrics per NixOS host ──────────────────────────
    log "Collecting Prometheus metrics..."
    echo "## Prometheus Metrics (node_exporter)"
    echo ""

    for ENTRY in "bees:localhost:9100" "bee:10.10.0.12:9100" "think:10.10.0.10:9100"; do
        IFS=':' read -r HOST IP PORT <<< "$ENTRY"
        INST="${IP}:${PORT}"

        echo "### $HOST ($INST)"
        echo ""

        # CPU
        CPU=$(prom_val "100 - (avg(rate(node_cpu_seconds_total{mode=\"idle\",instance=\"$INST\"}[$RANGE])) * 100)")
        echo "CPU usage: ${CPU}%"

        # Memory
        MEM=$(prom_val "(1 - node_memory_MemAvailable_bytes{instance=\"$INST\"} / node_memory_MemTotal_bytes{instance=\"$INST\"}) * 100")
        echo "Memory usage: ${MEM}%"

        # Load
        LOAD=$(prom_val "node_load1{instance=\"$INST\"}")
        echo "Load (1m): ${LOAD}"

        # Uptime
        UPTIME=$(prom_val "(time() - node_boot_time_seconds{instance=\"$INST\"}) / 3600")
        echo "Uptime: ${UPTIME}h"

        # Filesystems (all real mounts, not tmpfs/overlay)
        echo "Filesystems:"
        prom_labels "(1 - node_filesystem_avail_bytes{instance=\"$INST\",fstype!~\"tmpfs|overlay|squashfs|nsfs\"} / node_filesystem_size_bytes{instance=\"$INST\",fstype!~\"tmpfs|overlay|squashfs|nsfs\"}) * 100" "mountpoint" \
            | while read -r line; do
                if [ -n "$line" ] && [ "$line" != "  N/A" ]; then
                    echo "${line}%"
                else
                    echo "$line"
                fi
            done

        echo ""
    done

    # ── Network traffic overview ────────────────────────────────────
    echo "### Network Traffic (avg bytes/sec over ${RANGE})"
    for ENTRY in "bees:localhost:9100" "bee:10.10.0.12:9100" "think:10.10.0.10:9100"; do
        IFS=':' read -r HOST IP PORT <<< "$ENTRY"
        INST="${IP}:${PORT}"
        RX=$(prom_val "sum(rate(node_network_receive_bytes_total{instance=\"$INST\",device!~\"lo|docker.*|br-.*|veth.*\"}[$RANGE]))")
        TX=$(prom_val "sum(rate(node_network_transmit_bytes_total{instance=\"$INST\",device!~\"lo|docker.*|br-.*|veth.*\"}[$RANGE]))")
        echo "  $HOST — RX: ${RX} B/s, TX: ${TX} B/s"
    done
    echo ""

    # ── bees: local logs and status ────────────────────────────────
    log "Collecting bees local logs..."
    echo "## bees — Local Logs & Status"
    echo ""

    echo "### Failed systemd units"
    systemctl --failed --no-pager 2>/dev/null | head -20 || echo "(none)"
    echo ""

    echo "### Journal errors (last ${HOURS}h, last 50 lines)"
    journalctl -p err --since "$HOURS hours ago" --no-pager -q 2>/dev/null | tail -50 || echo "(none)"
    echo ""

    echo "### dmesg errors/warnings (last 20)"
    dmesg -l err,warn 2>/dev/null | tail -20 || echo "(none)"
    echo ""

    # ── bee: remote via SSH ────────────────────────────────────────
    log "Collecting bee remote data..."
    echo "## bee — Remote Data (SSH)"
    echo ""
    if ssh_reachable "crussell@10.10.0.12"; then
        echo "### Failed systemd units"
        ssh_cmd "crussell@10.10.0.12" "systemctl --failed --no-pager 2>/dev/null | head -20"
        echo ""

        echo "### User service failures"
        ssh_cmd "crussell@10.10.0.12" "XDG_RUNTIME_DIR=/run/user/\$(id -u) systemctl --user --failed --no-pager 2>/dev/null | head -20"
        echo ""

        echo "### Journal errors (last ${HOURS}h)"
        ssh_cmd "crussell@10.10.0.12" "journalctl -p err --since '$HOURS hours ago' --no-pager -q 2>/dev/null | tail -40"
        echo ""

        echo "### Memory & Disk"
        ssh_cmd "crussell@10.10.0.12" "free -h; echo '---'; df -h / /mnt/backups 2>/dev/null"
        echo ""
    else
        echo "**Host unreachable**"
        echo ""
    fi

    # ── think: remote via SSH ──────────────────────────────────────
    log "Collecting think remote data..."
    echo "## think — Remote Data (SSH)"
    echo ""
    if ssh_reachable "crussell@10.10.0.10"; then
        echo "### Journal errors (last ${HOURS}h)"
        ssh_cmd "crussell@10.10.0.10" "journalctl -p err --since '$HOURS hours ago' --no-pager -q 2>/dev/null | tail -30"
        echo ""

        echo "### Memory & Disk"
        ssh_cmd "crussell@10.10.0.10" "free -h; echo '---'; df -h /"
        echo ""
    else
        echo "**Host unreachable** (expected if sleeping/offline)"
        echo ""
    fi

    # ── nas: remote via SSH ────────────────────────────────────────
    log "Collecting nas remote data..."
    echo "## nas — Remote Data (SSH)"
    echo ""
    if ssh_reachable "root@10.10.0.3"; then
        echo "### System status"
        ssh_cmd "root@10.10.0.3" "uptime; echo '---'; free -h; echo '---'; df -h"
        echo ""

        echo "### ZFS Pool Status"
        ssh_cmd "root@10.10.0.3" "zpool status 2>/dev/null || echo 'zpool not available'"
        echo ""
    else
        echo "**Host unreachable**"
        echo ""
    fi

    # ── gateway: remote via SSH ────────────────────────────────────
    log "Collecting gateway remote data..."
    echo "## gateway — Remote Data (SSH)"
    echo ""
    if ssh_reachable "root@10.10.0.2"; then
        echo "### System status"
        ssh_cmd "root@10.10.0.2" "uptime; echo '---'; free -h; echo '---'; df -h"
        echo ""

        echo "### Service status (nginx, nebula)"
        ssh_cmd "root@10.10.0.2" "systemctl is-active nginx nebula 2>/dev/null"
        echo ""

        echo "### Journal errors (last ${HOURS}h)"
        ssh_cmd "root@10.10.0.2" "journalctl -p err --since '$HOURS hours ago' --no-pager -q 2>/dev/null | tail -30"
        echo ""
    else
        echo "**Host unreachable**"
        echo ""
    fi

} > "$DATA"

DATA_SIZE=$(wc -c < "$DATA")
log "Collected ${DATA_SIZE} bytes of data"

# ══════════════════════════════════════════════════════════════════════
# AI ANALYSIS
# ══════════════════════════════════════════════════════════════════════

if [ "$MODE" = "daily" ]; then
    INSTRUCTION='MODE: DAILY REPORT

Analyze the infrastructure data and produce a daily health report for every machine. For each machine, give a one-line status summary with emoji (✅ healthy, ⚠️ warning, ❌ critical), then brief notes on anything notable. End with an "Action Items" section if anything needs attention. Keep the entire report under 3000 characters. Do not include this instruction in your output.'
else
    INSTRUCTION='MODE: CRITICAL CHECK

Analyze the infrastructure data for critical issues only. If everything is operating normally with no issues requiring attention, respond with exactly the single word ALL_CLEAR and nothing else.
If there are critical issues needing immediate attention, start with CRITICAL_ALERT: and list only the problems. Keep it under 1000 characters. Do not include this instruction in your output.'
fi

log "Running pi analysis..."
REPORT=$(pi -p \
    -nt \
    --no-session \
    -ne -ns -nc \
    --system-prompt "$(cat "$PROMPT_FILE")" \
    @"$DATA" \
    "$INSTRUCTION" 2>/dev/null) || {
    log "ERROR: pi analysis failed (exit $?)"
    curl -sf \
        -H "Title: ⚠️ Homelab Monitor Error" \
        -H "Priority: high" \
        -H "Tags: warning" \
        -d "Monitor failed to generate report (pi exited non-zero). Check: journalctl -u homelab-monitor-${MODE}" \
        "$NTFY_URL/$NTFY_TOPIC" 2>/dev/null || true
    exit 1
}

log "AI report generated: $(echo "$REPORT" | wc -c) bytes"

# ══════════════════════════════════════════════════════════════════════
# NOTIFICATION
# ══════════════════════════════════════════════════════════════════════

send_ntfy() {
    local title="$1"
    local priority="$2"
    local tags="$3"
    local body="$4"

    # Truncate to ntfy limit (4096 bytes) with notice
    local body_bytes
    body_bytes=$(echo "$body" | wc -c)
    if [ "$body_bytes" -gt 4000 ]; then
        body=$(echo "$body" | head -c 3900)"
[Report truncated. Full output in: journalctl -u homelab-monitor-${MODE}]"
    fi

    curl -sf \
        -H "Title: $title" \
        -H "Priority: $priority" \
        -H "Tags: $tags" \
        -d "$body" \
        "$NTFY_URL/$NTFY_TOPIC" 2>/dev/null || true
}

if [ "$MODE" = "check" ]; then
    # Only alert if NOT all clear
    if echo "$REPORT" | grep -q "ALL_CLEAR"; then
        log "All clear — no notification sent"
    else
        log "Issues detected — sending alert"
        send_ntfy "⚠️ Homelab Alert" "high" "warning" "$REPORT"
    fi
else
    # Daily: always send
    log "Sending daily report"
    send_ntfy "☀️ Daily Homelab Report — $(date +%Y-%m-%d)" "low" "clipboard" "$REPORT"
fi

log "Done"

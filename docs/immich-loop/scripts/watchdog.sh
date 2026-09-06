#!/usr/bin/env bash
# immich-loop watchdog — no-agent health watch. Cron every 15m.
# Prints alerts to stdout (delivered to discord:#infra by the cron job);
# prints NOTHING when all is well.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOARD="immich-loop"
STATE="$REPO_DIR/.loop/watchdog-state"
mkdir -p "$STATE"

mark()  { [ -f "$STATE/$1" ]; }
setmark(){ mkdir -p "$STATE"; touch "$STATE/$1"; }
clmark(){ rm -f "$STATE/$1"; }
once()  { if mark "$1"; then return 1; fi; setmark "$1"; return 0; }

OUT=""

# 1. gateway alive
if ! systemctl is-active --quiet hermes-agent; then
  if once gateway-down; then
    OUT+="🔴 hermes-agent gateway DOWN — dispatcher not running (bee: systemctl status hermes-agent)"$'\n'
  fi
else
  clmark gateway-down
fi

# 2. board state
TASKS=$(hermes kanban --board "$BOARD" list --json 2>/dev/null || echo "[]")
declare -A COUNT=( [todo]=0 [ready]=0 [running]=0 [blocked]=0 [review]=0 [scheduled]=0 [triage]=0 [done]=0 )
while IFS='=' read -r st n; do COUNT[$st]=$n; done < <(jq -r '.[] | .status' <<<"$TASKS" 2>/dev/null | sort | uniq -c | awk '{print $2"="$1}')
PENDING=$(( COUNT[todo] + COUNT[ready] + COUNT[running] + COUNT[blocked] + COUNT[review] + COUNT[scheduled] + COUNT[triage] ))

while IFS=$'\t' read -r tid title; do
  [ -z "$tid" ] && continue
  if once "blocked-$tid"; then
    OUT+="⛔ immich-loop blocked: $tid — $title"$'\n'
  fi
done < <(jq -r '.[] | select(.status=="blocked") | [.id, .title] | @tsv' <<<"$TASKS" 2>/dev/null)
for f in "$STATE"/blocked-*; do
  [ -e "$f" ] || continue
  tid="${f##*blocked-}"
  if [ "$(jq -r --arg i "$tid" '.[] | select(.id==$i) | .status' <<<"$TASKS" 2>/dev/null)" != "blocked" ]; then
    clmark "blocked-$tid"
  fi
done

while IFS=$'\t' read -r tid title; do
  [ -z "$tid" ] && continue
  if once "review-$tid"; then
    OUT+="👀 immich-loop review: $tid — $title"$'\n'
  fi
done < <(jq -r '.[] | select(.status=="review") | [.id, .title] | @tsv' <<<"$TASKS" 2>/dev/null)
for f in "$STATE"/review-*; do
  [ -e "$f" ] || continue
  tid="${f##*review-}"
  if [ "$(jq -r --arg i "$tid" '.[] | select(.id==$i) | .status' <<<"$TASKS" 2>/dev/null)" != "review" ]; then
    clmark "review-$tid"
  fi
done

# 3. stale running claims (no heartbeat update > 45 min)
NOW=$(date +%s)
while IFS=$'\t' read -r tid hb; do
  [ -z "$tid" ] && continue
  AGE=$(( NOW - hb ))
  if [ "$AGE" -gt 2700 ]; then
    if once "stale-$tid"; then
      OUT+="🐌 immich-loop stale claim: $tid (no heartbeat ${AGE}s) — operator: hermes kanban --board $BOARD reclaim $tid"$'\n'
    fi
  else
    clmark "stale-$tid"
  fi
done < <(hermes kanban --board "$BOARD" list --json 2>/dev/null | jq -r '.[] | select(.status=="running") | [.id, (.heartbeat_at // 0)] | @tsv' 2>/dev/null)

# 4. board complete -> final report once, then auto-pause marker
if [ "$PENDING" -eq 0 ] && [ "${COUNT[done]}" -gt 0 ]; then
  if once board-complete; then
    OUT+="🏁 immich-loop board COMPLETE (${COUNT[done]} tasks done). Operator: review, archive board, pause this watchdog."$'\n'
  fi
else
  clmark board-complete
fi

printf '%s' "$OUT"
exit 0

#!/usr/bin/env bash
# scripts/deploy.sh — cn homelab deploy helper
#
# Usage (run from anywhere on bee):
#   deploy.sh <host> [host2 ...]
#   deploy.sh bee
#   deploy.sh bee bees
#   deploy.sh gateway
#
# What it does:
#   1. Pushes any unpushed local commits from bee → origin (GitHub)
#   2. SSHes into bees (the deploy origin), pulls origin, runs
#      `nix run .#deploy -- <hosts>` fully detached so it survives session drops
#   3. Tails the log on bees until done, reporting success/failure here
#
# bee self-deploy bounce trap: activating a new generation on bee restarts
# hermes-agent, killing this script's session. We detect this case and
# schedule the activation via `systemd-run` from root SSH on bee so the
# switch completes independently.

set -euo pipefail

CN_DIR="$HOME/Code/cn"
BEES_SSH="crussell@10.10.0.6"   # bees Nebula IP — always the deploy origin
BEE_ROOT_SSH="root@10.10.0.12"  # bee root — for self-deploy bounce trap only
HOSTS=("$@")

# ── Validate args ─────────────────────────────────────────────────────────────
if [[ ${#HOSTS[@]} -eq 0 ]]; then
    echo "Usage: deploy.sh <host> [host2 ...]" >&2
    echo "Hosts: bee bees nas gateway" >&2
    exit 1
fi

VALID_HOSTS=(bee bees nas gateway)
for h in "${HOSTS[@]}"; do
    ok=0
    for v in "${VALID_HOSTS[@]}"; do [[ "$h" == "$v" ]] && ok=1; done
    if [[ $ok -eq 0 ]]; then
        echo "Unknown host: $h (valid: ${VALID_HOSTS[*]})" >&2
        exit 1
    fi
done

HOSTS_STR="${HOSTS[*]}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG="/tmp/cn-deploy-${HOSTS_STR// /_}-${TIMESTAMP}.log"

echo "▶ cn deploy: [${HOSTS_STR}] — $(date)"

# ── Step 1: Push any local commits from bee → origin ─────────────────────────
echo "  push …"
cd "$CN_DIR"
AHEAD=$(git rev-list --count "origin/main..HEAD" 2>/dev/null || echo 0)
if [[ "$AHEAD" -gt 0 ]]; then
    echo "  $AHEAD commit(s) ahead of origin — pushing …"
    git push origin main
    echo "  pushed ✓"
else
    echo "  nothing to push"
fi

# ── Step 2: Detect bee self-deploy ────────────────────────────────────────────
DEPLOYING_BEE=0
for h in "${HOSTS[@]}"; do [[ "$h" == "bee" ]] && DEPLOYING_BEE=1; done

# ── Step 3: Kick off detached deploy on bees ──────────────────────────────────
echo "  starting deploy on bees (log: bees:${LOG}) …"

# NB: args MUST be single-quoted inside the remote command string — ssh
# joins argv with spaces and the remote shell re-splits, so an unquoted
# "gateway bees" arrives as two words and HOSTS_STR=$2 silently keeps
# only "gateway" (multi-host deploys ran just the first host, false green).
ssh -o IdentitiesOnly=yes -o ConnectTimeout=10 "$BEES_SSH" "bash -s -- '$LOG' '$HOSTS_STR'" << 'REMOTE'
LOG="$1"
HOSTS_STR="$2"
cd ~/Code/cn
LOCAL=$(git rev-parse HEAD)
REMOTE_REV=$(git rev-parse origin/main 2>/dev/null || git fetch --quiet origin && git rev-parse origin/main)
if [[ "$LOCAL" != "$REMOTE_REV" ]]; then
    git pull --ff-only origin main
fi
# Detach fully — survives SSH disconnect and any session drop on bee
setsid nohup bash -c "nix run .#deploy -- ${HOSTS_STR} >'${LOG}' 2>&1; echo EXIT:\$? >>'${LOG}'" </dev/null >/dev/null 2>&1 &
echo "deploy started (pid $!)"
REMOTE

echo "  tailing log — Ctrl-C is safe, deploy continues on bees regardless"
echo ""

# ── Step 4: Tail log from bees until done ─────────────────────────────────────
LAST_LINE=0
DONE=0
for i in $(seq 1 360); do   # max 30 min (360 × 5s)
    sleep 5
    OUTPUT=$(ssh -o IdentitiesOnly=yes -o ConnectTimeout=8 "$BEES_SSH" \
        "test -f '${LOG}' && tail -n +$((LAST_LINE + 1)) '${LOG}' || true" 2>/dev/null || true)
    if [[ -n "$OUTPUT" ]]; then
        echo "$OUTPUT"
        LINES=$(echo "$OUTPUT" | wc -l)
        LAST_LINE=$((LAST_LINE + LINES))
        if echo "$OUTPUT" | grep -q "All hosts deployed"; then
            DONE=1; break
        fi
        if echo "$OUTPUT" | grep -qE "^EXIT:[^0]|^error:|failed with exit code"; then
            echo ""
            echo "✗ deploy failed — full log on bees: ${LOG}" >&2
            exit 1
        fi
    fi
done

if [[ $DONE -eq 0 ]]; then
    echo "✗ timed out waiting for deploy — check bees:${LOG}" >&2
    exit 1
fi

echo ""
echo "✓ All hosts deployed [${HOSTS_STR}]"

# ── Step 5: bee self-deploy bounce ────────────────────────────────────────────
# If bee was in the host set, bees pushed the new closure to bee's Nix store
# but the activation (switch-to-configuration) kills hermes-agent — i.e. kills
# this very script. We schedule it via systemd-run from root SSH on bee so it
# runs independently of whether this session survives.
if [[ $DEPLOYING_BEE -eq 1 ]]; then
    echo ""
    echo "  bee was in the deploy set — scheduling activation via systemd-run …"
    echo "  (hermes-agent will restart; this session may drop — that's expected)"

    # The newest system-*-link on bee is the just-built generation.
    # NB: -d is required — without it ls lists the symlink's TARGET dir
    # (the generation store path) and head -1 grabs the "path:" header
    # line, which then fails "Failed to find executable".
    NEW_GEN=$(ssh -o IdentitiesOnly=yes -o ConnectTimeout=8 "$BEE_ROOT_SSH" \
        "ls -dt /nix/var/nix/profiles/system-*-link | head -1 | xargs readlink -f" 2>/dev/null || true)

    if [[ -z "$NEW_GEN" ]]; then
        echo "  ⚠ could not determine new generation path on bee — activate manually:" >&2
        echo "    ssh root@10.10.0.12 systemd-run --collect /nix/store/<gen>/bin/switch-to-configuration switch" >&2
    else
        echo "  new generation: $NEW_GEN"
        ssh -o IdentitiesOnly=yes -o ConnectTimeout=8 "$BEE_ROOT_SSH" \
            "systemd-run --collect --unit=cn-switch-bee \
             '${NEW_GEN}/bin/switch-to-configuration' switch" \
        && echo "  activation scheduled ✓ (hermes will restart shortly)" \
        || echo "  ⚠ failed to schedule — activate manually on bee" >&2
    fi
fi

echo ""
echo "Done."

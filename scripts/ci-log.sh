#!/usr/bin/env bash
# scripts/ci-log.sh — fetch Forgejo Actions job logs for chad/cn.
#
# This Forgejo build predates the /actions/jobs/{id}/logs API endpoints
# (and serves no /api/v3 for `gh`), but job logs are stored server-side
# as zstd files with their paths recorded in the DB — so we read them
# from the gateway, where we already hold root SSH for ops.
#
# Usage:
#   scripts/ci-log.sh            # latest run
#   scripts/ci-log.sh 65         # run by UI index (the number in the
#                                # /actions/runs/<n> URL) or internal id
#   scripts/ci-log.sh 65 | tail  # it's just stdout — pipe freely
#
# Requires: ssh key with root@gateway (10.10.0.2), same as other
# gateway ops (see AGENTS.md SSH Access).
set -euo pipefail

RUN="${1:-latest}"

# NB: empty args don't survive ssh argv passing — always send a sentinel.
ssh -F /dev/null -o IdentitiesOnly=yes -o ConnectTimeout=10 \
  -i "$HOME/.ssh/id_ed25519" root@10.10.0.2 'bash -s' -- "$RUN" <<'REMOTE'
set -eu
run="$1"
[ "$run" = latest ] && run=""
DB=/var/lib/forgejo/data/forgejo.db
LOGROOT=/var/lib/forgejo/data/actions_log

sq=$(nix --extra-experimental-features nix-command shell nixpkgs#sqlite nixpkgs#zstd \
      -c sh -c 'command -v sqlite3')
zc=$(nix --extra-experimental-features nix-command shell nixpkgs#sqlite nixpkgs#zstd \
      -c sh -c 'command -v zstdcat')
q() { "$sq" "$DB" "$1"; }

# Resolve run: prefer the UI index (the number in /actions/runs/<n>
# URLs — what users actually see), fall back to internal id.
if [ -n "$run" ]; then
  rid=$(q "SELECT id FROM action_run WHERE \"index\"=${run} LIMIT 1;")
  [ -z "$rid" ] && rid=$(q "SELECT id FROM action_run WHERE id=${run} LIMIT 1;")
else
  rid=$(q "SELECT id FROM action_run ORDER BY id DESC LIMIT 1;")
fi
[ -n "$rid" ] || { echo "run not found: ${run:-<latest>}" >&2; exit 1; }

title=$(q "SELECT title FROM action_run WHERE id=${rid};")
idx=$(q "SELECT \"index\" FROM action_run WHERE id=${rid};")
echo "== run #${idx} (id ${rid}): ${title}"

q "SELECT id FROM action_run_job WHERE run_id=${rid} ORDER BY id;" \
| while read -r jid; do
    name=$(q "SELECT name FROM action_run_job WHERE id=${jid};")
    st=$(q "SELECT status FROM action_run_job WHERE id=${jid};")
    case "$st" in
      1) word=success ;; 2) word=failure ;; 3) word=cancelled ;;
      4) word=skipped ;; 5) word=running ;; *) word="status($st)" ;;
    esac
    echo "-- job ${jid} [${name}] ${word}"
    lf=$(q "SELECT log_filename FROM action_task WHERE job_id=${jid};")
    if [ -n "$lf" ] && [ -f "${LOGROOT}/${lf}" ]; then
      "$zc" "${LOGROOT}/${lf}"
    else
      echo "   (no log uploaded yet)"
    fi
  done
REMOTE

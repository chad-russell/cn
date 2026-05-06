#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -eq 0 ]]; then
  echo "Usage: $0 <ha arguments...>" >&2
  echo "Example: $0 apps list --raw-json" >&2
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
quoted_args="$(printf '%q ' "$@")"

exec "$script_dir/ha-ssh.sh" \
  "TOKEN=\$(cat /run/s6/container_environment/SUPERVISOR_TOKEN); ha --api-token \"\$TOKEN\" $quoted_args"

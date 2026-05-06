#!/usr/bin/env bash
set -euo pipefail

HOST="${HA_HAOS_HOST:-192.168.20.51}"
USER_NAME="${HA_HAOS_USER:-hassio}"
SSH_OPTS=(
  -o IdentitiesOnly=yes
  -o PreferredAuthentications=password
  -o PubkeyAuthentication=no
  -o StrictHostKeyChecking=accept-new
)

if [[ -n "${HA_SSH_PASSWORD:-}" ]]; then
  askpass_file="$(mktemp)"
  trap 'rm -f "$askpass_file"' EXIT
  cat >"$askpass_file" <<EOF
#!/bin/sh
printf '%s\n' '${HA_SSH_PASSWORD}'
EOF
  chmod 700 "$askpass_file"
  exec env DISPLAY=:0 SSH_ASKPASS="$askpass_file" SSH_ASKPASS_REQUIRE=force \
    setsid ssh "${SSH_OPTS[@]}" "$USER_NAME@$HOST" "$@"
fi

exec ssh "${SSH_OPTS[@]}" "$USER_NAME@$HOST" "$@"

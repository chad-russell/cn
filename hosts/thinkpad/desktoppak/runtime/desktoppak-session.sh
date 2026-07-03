#!/usr/bin/env bash
#
# desktoppak-session — in-sandbox session wrapper for the GDM-launched prototype.

set -euo pipefail

: "${HOME:?HOME is required}"
: "${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is required}"
: "${DESKTOPPAK_SESSION_EXEC:?DESKTOPPAK_SESSION_EXEC is required}"

log_file="${DESKTOPPAK_SESSION_LOG_FILE:-$HOME/session.log}"
mkdir -p "$(dirname "$log_file")" "$HOME/Pictures/Screenshots"
[ -f "$log_file" ] && cp -f "$log_file" "$log_file.old" 2>/dev/null || true
: >"$log_file"

log() {
  printf '[desktoppak-session] %s\n' "$*" >>"$log_file"
}

publish_wayland_env() {
  local sock="${1:?socket path required}"
  local wayland_display
  wayland_display="$(basename "$sock")"

  export WAYLAND_DISPLAY="$wayland_display"
  log "detected WAYLAND_DISPLAY=$WAYLAND_DISPLAY"

  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user import-environment \
      WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE \
      >>"$log_file" 2>&1 || log "WARN: systemctl --user import-environment failed"
  fi

  if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --systemd \
      WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE \
      >>"$log_file" 2>&1 || log "WARN: dbus-update-activation-environment failed"
  fi
}

log "starting session exec: $DESKTOPPAK_SESSION_EXEC"
"$DESKTOPPAK_SESSION_EXEC" "$@" >>"$log_file" 2>&1 &
session_pid=$!

trap 'kill -TERM "$session_pid" 2>/dev/null || true' TERM
trap 'kill -INT "$session_pid" 2>/dev/null || true' INT
trap 'kill -HUP "$session_pid" 2>/dev/null || true' HUP

for _ in $(seq 1 100); do
  if sock="$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -type s -name 'wayland-*' | head -n1)" && [ -n "$sock" ]; then
    publish_wayland_env "$sock"
    break
  fi
  if ! kill -0 "$session_pid" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

wait "$session_pid"
status=$?
log "session exited with status $status"
exit "$status"

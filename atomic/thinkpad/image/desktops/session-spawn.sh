#!/usr/bin/env bash
#
# session-spawn — launch host/Flatpak apps from the sandboxed desktop session.
#
# Uses `flatpak-spawn --host`, which asks the HOST's flatpak-session-helper to
# run the command on the host.
#
# Because the spawn originates inside the session, $WAYLAND_DISPLAY already
# targets THIS compositor — no session.env handoff or host-side guessing is
# needed, even when multiple desktop sessions are running at once.
#
# Usage:
#   session-spawn terminal              # host terminal   ($DESKTOP_TERMINAL_CMD)
#   session-spawn browser               # browser Flatpak ($DESKTOP_BROWSER_FLATPAK_APP)
#   session-spawn editor                # editor Flatpak  ($DESKTOP_EDITOR_FLATPAK_APP)
#   session-spawn flatpak <app-id> [...]  # any Flatpak by app-id
#   session-spawn host <cmd> [args...]    # any host binary
#
# Log: desktop-blueprint/logs/session-spawn.log

set -uo pipefail

LOG_DIR="/run/desktop-blueprint/logs"
LOG_FILE="${LOG_DIR}/session-spawn.log"
mkdir -p "$LOG_DIR"

log() { printf '[session-spawn] %s\n' "$*" >>"$LOG_FILE"; }

mode="${1:-}"
shift || true

case "$mode" in
  terminal) kind=host;    target="${DESKTOP_TERMINAL_CMD:-/usr/bin/ptyxis}" ;;
  browser)  kind=flatpak; target="${DESKTOP_BROWSER_FLATPAK_APP:-app.zen_browser.zen}" ;;
  editor)   kind=flatpak; target="${DESKTOP_EDITOR_FLATPAK_APP:-org.gnome.TextEditor}" ;;
  flatpak)  kind=flatpak; target="${1:?session-spawn: flatpak mode needs an app-id}"; shift ;;
  host)     kind=host;    target="${1:?session-spawn: host mode needs a command}"; shift ;;
  ""|*)
    log "FAIL: unknown mode '${mode:-<none>}'"
    echo "usage: session-spawn {terminal|browser|editor|flatpak <id>|host <cmd>}" >&2
    exit 2 ;;
esac

[ -n "${WAYLAND_DISPLAY:-}" ] || { log "FAIL: WAYLAND_DISPLAY unset — not under a live compositor"; exit 1; }

case "$kind" in
  flatpak) host_cmd=(flatpak run "$target" "$@") ;;
  host)    host_cmd=("$target" "$@") ;;
esac

log "mode=$mode kind=$kind target=$target extra=$(printf ' %q' "$@" </dev/null)"
log "  WAYLAND_DISPLAY=$WAYLAND_DISPLAY XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-}"
log "  calling: flatpak-spawn --host -- ${host_cmd[*]}"

if flatpak-spawn --host \
      --directory="${XDG_RUNTIME_DIR:-/tmp}" \
      --env="WAYLAND_DISPLAY=$WAYLAND_DISPLAY" \
      --env="XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-}" \
      --env="XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-niri}" \
      --env="XDG_SESSION_DESKTOP=${XDG_SESSION_DESKTOP:-niri}" \
      --env="XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-wayland}" \
      -- "${host_cmd[@]}" >>"$LOG_FILE" 2>&1; then
  log "PASS: launched $target"
  exit 0
else
  rc=$?
  log "FAIL (rc=$rc): flatpak-spawn --host failed for $target"
  exit "$rc"
fi

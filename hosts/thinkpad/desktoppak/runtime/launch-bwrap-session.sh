#!/usr/bin/env bash
set -euo pipefail

TERMINAL_CMD="${DESKTOP_TERMINAL_CMD:-/usr/bin/ptyxis}"
BROWSER_APP="${DESKTOP_BROWSER_FLATPAK_APP:-app.zen_browser.zen}"
EDITOR_APP="${DESKTOP_EDITOR_FLATPAK_APP:-org.gnome.TextEditor}"
DBUS_SYSTEM_SOCKET="/run/dbus/system_bus_socket"
DBUS_SYSTEM_BUS_ADDRESS="unix:path=${DBUS_SYSTEM_SOCKET}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
: "${DESKTOPPAK_STATE_ROOT:?DESKTOPPAK_STATE_ROOT is required}"
: "${DESKTOPPAK_ROOTFS_DIR:?DESKTOPPAK_ROOTFS_DIR is required}"
STATE_ROOT="${DESKTOPPAK_STATE_ROOT}"
ROOTFS_DIR="${DESKTOPPAK_ROOTFS_DIR}"
SESSION_ROOT="${STATE_ROOT}/session"
XDG_CONFIG_DIR="${DESKTOPPAK_CONFIG_ROOT:-${SESSION_ROOT}/xdg-config}"
XDG_STATE_DIR="${SESSION_ROOT}/xdg-state"
XDG_DATA_DIR="${SESSION_ROOT}/xdg-data"
XDG_CACHE_DIR="${SESSION_ROOT}/xdg-cache"
LOG_DIR="${SESSION_ROOT}/logs"

SESSION_HELPER="${SCRIPT_DIR}/desktoppak-session.sh"
DESKTOPPAK_SPAWN="${SCRIPT_DIR}/desktoppak-spawn.sh"
DEV_CONFIG_FILE="${DESKTOPPAK_DEV_CONFIG_FILE:-}"
MANIFEST_REL="/usr/share/desktoppak/manifest.json"

: "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
LAUNCH_LOG="${XDG_RUNTIME_DIR}/desktoppak-launch.log"
exec >>"$LAUNCH_LOG" 2>&1

echo "=== $(date -Is) desktoppak launch ==="
echo "USER=${USER:-} HOME=${HOME:-} XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-}"
echo "SCRIPT_DIR=$SCRIPT_DIR"
echo "STATE_ROOT=$STATE_ROOT"
echo "ROOTFS_DIR=$ROOTFS_DIR"

[ -d "$XDG_RUNTIME_DIR" ] || { echo "ERROR: XDG_RUNTIME_DIR missing: $XDG_RUNTIME_DIR"; exit 1; }
[ -S "$DBUS_SYSTEM_SOCKET" ] || { echo "ERROR: missing system bus socket: $DBUS_SYSTEM_SOCKET"; exit 1; }
command -v bwrap >/dev/null 2>&1 || { echo "ERROR: bwrap not found"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 not found"; exit 1; }

MANIFEST_PATH="${ROOTFS_DIR}${MANIFEST_REL}"
if [ ! -f "$MANIFEST_PATH" ]; then
  echo "ERROR: missing manifest at $MANIFEST_PATH"
  echo "HINT: install or update the desktoppak first so its rootfs is materialized."
  exit 1
fi

eval "$(python3 - "$MANIFEST_PATH" <<'PY'
import json, shlex, sys
p = sys.argv[1]
with open(p, 'r', encoding='utf-8') as f:
    m = json.load(f)
env = m.get('env', {})
config_seeds = []
for item in m.get('config', {}).get('seed', []):
    source = item.get('source')
    target = item.get('target')
    if source and target and target.startswith('/home/session/.config/'):
        config_seeds.append(f"{source}\t{target}")
host_paths = []
for item in m.get('host_paths', []):
    host_paths.append("\t".join([
        item.get('type', 'ro'),
        item.get('host', ''),
        item.get('guest', ''),
        '1' if item.get('optional', False) else '0',
    ]))
pairs = {
    'SESSION_NAME': m.get('name', 'niri'),
    'DISPLAY_NAME': m.get('display_name', 'Niri (bubblewrap)'),
    'SESSION_EXEC': m.get('exec', '/usr/bin/niri'),
    'SESSION_DESKTOP': env.get('XDG_SESSION_DESKTOP', 'niri'),
    'CURRENT_DESKTOP': env.get('XDG_CURRENT_DESKTOP', 'niri'),
    'SESSION_TYPE': env.get('XDG_SESSION_TYPE', 'wayland'),
    'LIBSEAT_BACKEND_VALUE': env.get('LIBSEAT_BACKEND', 'logind'),
    'XDG_DATA_DIRS_VALUE': env.get('XDG_DATA_DIRS', '/usr/local/share:/usr/share'),
    'QT_QPA_PLATFORM_VALUE': env.get('QT_QPA_PLATFORM', 'wayland'),
    'QT_WAYLAND_DISABLE_WINDOWDECORATIONS_VALUE': env.get('QT_WAYLAND_DISABLE_WINDOWDECORATIONS', ''),
    'CONFIG_SEEDS': '\n'.join(config_seeds),
    'HOST_PATHS': '\n'.join(host_paths),
}
for k, v in pairs.items():
    print(f'{k}={shlex.quote(v)}')
PY
)"

expand_host_path() {
  local p="$1"
  p="${p//\$HOME/$HOME}"
  p="${p//\$XDG_RUNTIME_DIR/$XDG_RUNTIME_DIR}"
  printf '%s\n' "$p"
}

add_parent_dirs() {
  local target="$1"
  while [ "$target" != "/" ] && [ "$target" != "." ] && [ -n "$target" ]; do
    BWRAP_DIRS["$target"]=1
    target="$(dirname "$target")"
  done
}

declare -A BWRAP_DIRS=()
declare -a EXTRA_BIND_ARGS=()

SESSION_ANCHOR_UNIT="desktoppak-graphical-session-${SESSION_NAME:-session}-$$.service"

mkdir -p \
  "$XDG_CONFIG_DIR" \
  "$XDG_STATE_DIR" \
  "$XDG_DATA_DIR" \
  "$XDG_CACHE_DIR" \
  "$LOG_DIR"

while IFS=$'\t' read -r seed_src seed_target; do
  [ -n "${seed_src:-}" ] || continue
  [ -n "${seed_target:-}" ] || continue
  host_target="${XDG_CONFIG_DIR}/${seed_target#/home/session/.config/}"
  mkdir -p "$(dirname "$host_target")"
  seed_source=""
  if [ -n "$DEV_CONFIG_FILE" ] && [ -f "$DEV_CONFIG_FILE" ] && [ "$seed_target" = "/home/session/.config/niri/config.kdl" ]; then
    seed_source="$DEV_CONFIG_FILE"
  else
    candidate="${ROOTFS_DIR}${seed_src}"
    [ -f "$candidate" ] || { echo "ERROR: missing config seed source $candidate"; exit 1; }
    seed_source="$candidate"
  fi
  if [ "${NIRI_BWRAP_SYNC_CONFIG:-0}" = "1" ] || [ ! -e "$host_target" ]; then
    install -m 0644 "$seed_source" "$host_target"
  fi
done <<< "$CONFIG_SEEDS"

while IFS=$'\t' read -r bind_type bind_host bind_guest bind_optional; do
  [ -n "${bind_type:-}" ] || continue
  bind_host="$(expand_host_path "$bind_host")"
  bind_guest="$(expand_host_path "$bind_guest")"
  if [ ! -e "$bind_host" ]; then
    [ "${bind_optional:-0}" = "1" ] && continue
    echo "ERROR: required host path missing: $bind_host"
    exit 1
  fi
  add_parent_dirs "$bind_guest"
  case "$bind_type" in
    ro) EXTRA_BIND_ARGS+=(--ro-bind-try "$bind_host" "$bind_guest") ;;
    rw) EXTRA_BIND_ARGS+=(--bind-try "$bind_host" "$bind_guest") ;;
    *) echo "ERROR: unsupported host path bind type: $bind_type"; exit 1 ;;
  esac
done <<< "$HOST_PATHS"

[ -x "$ROOTFS_DIR$SESSION_EXEC" ] || { echo "ERROR: rootfs missing session exec at $ROOTFS_DIR$SESSION_EXEC"; exit 1; }

echo "Starting session"
echo "  name:         $SESSION_NAME"
echo "  display:      $DISPLAY_NAME"
echo "  exec:         $SESSION_EXEC"
echo "  rootfs:       $ROOTFS_DIR"
echo "  state root:   $STATE_ROOT"
echo "  session root: $SESSION_ROOT"
echo "  runtime dir:  $XDG_RUNTIME_DIR"
echo "  session type: $SESSION_TYPE"
echo "  logs:         $LOG_DIR"
echo "  launch log:   $LAUNCH_LOG"

action_cleanup() {
  local rc=$?
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user stop "$SESSION_ANCHOR_UNIT" >/dev/null 2>&1 || true
  fi
  exit "$rc"
}

trap action_cleanup EXIT INT TERM HUP

if command -v systemd-run >/dev/null 2>&1; then
  echo "Starting graphical-session anchor: $SESSION_ANCHOR_UNIT"
  if ! systemd-run \
      --user \
      --unit="$SESSION_ANCHOR_UNIT" \
      --quiet \
      --collect \
      --service-type=exec \
      --description="desktoppak graphical session anchor: $SESSION_NAME" \
      --property=Wants=graphical-session.target \
      --property=BindsTo=graphical-session.target \
      --property=PartOf=graphical-session.target \
      --property=After=graphical-session-pre.target \
      --property=Slice=session.slice \
      /usr/bin/sleep infinity; then
    echo "WARN: failed to start graphical-session anchor unit"
  fi
else
  echo "WARN: systemd-run not found; graphical-session.target may not stay active"
fi

declare -a BWRAP_ARGS=(
  --ro-bind "$ROOTFS_DIR" /
  --dev-bind /dev /dev
  --proc /proc
  --ro-bind /sys /sys
  --tmpfs /run
  --dir /run/dbus
  --dir /run/udev
  --dir /run/systemd
  --ro-bind-try /run/dbus /run/dbus
  --ro-bind-try /run/udev /run/udev
  --ro-bind-try /run/systemd /run/systemd
  --bind "$XDG_RUNTIME_DIR" "$XDG_RUNTIME_DIR"
  --tmpfs /tmp
  --dir /run/desktoppak
  --dir /run/desktoppak/bin
  --tmpfs /home
  --dir /home/session
  --dir /home/session/.local
)

for dir in "${!BWRAP_DIRS[@]}"; do
  case "$dir" in
    /|/run|/home) ;;
    *) BWRAP_ARGS+=(--dir "$dir") ;;
  esac
done

BWRAP_ARGS+=(
  --bind "$XDG_CONFIG_DIR" /home/session/.config
  --bind "$XDG_STATE_DIR" /home/session/.local/state
  --bind "$XDG_DATA_DIR" /home/session/.local/share
  --bind "$XDG_CACHE_DIR" /home/session/.cache
  --bind "$LOG_DIR" /run/desktoppak/logs
  --ro-bind "$SESSION_HELPER" /run/desktoppak/bin/desktoppak-session
  --ro-bind "$DESKTOPPAK_SPAWN" /run/desktoppak/bin/desktoppak-spawn
)

BWRAP_ARGS+=("${EXTRA_BIND_ARGS[@]}")

BWRAP_ARGS+=(
  --setenv HOME /home/session
  --setenv USER "${USER:-user}"
  --setenv LOGNAME "${LOGNAME:-${USER:-user}}"
  --setenv SHELL /bin/bash
  --setenv PATH "/run/desktoppak/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  --setenv XDG_CONFIG_HOME /home/session/.config
  --setenv XDG_STATE_HOME /home/session/.local/state
  --setenv XDG_DATA_HOME /home/session/.local/share
  --setenv XDG_CACHE_HOME /home/session/.cache
  --setenv XDG_DATA_DIRS "$XDG_DATA_DIRS_VALUE"
  --setenv XDG_RUNTIME_DIR "$XDG_RUNTIME_DIR"
  --setenv XDG_SESSION_ID "${XDG_SESSION_ID:-}"
  --setenv XDG_SESSION_TYPE "$SESSION_TYPE"
  --setenv XDG_SESSION_CLASS "${XDG_SESSION_CLASS:-user}"
  --setenv XDG_SESSION_DESKTOP "$SESSION_DESKTOP"
  --setenv XDG_CURRENT_DESKTOP "$CURRENT_DESKTOP"
  --setenv XDG_SEAT "${XDG_SEAT:-seat0}"
  --setenv XDG_VTNR "${XDG_VTNR:-}"
  --setenv GDK_BACKEND wayland
  --setenv QT_QPA_PLATFORM "$QT_QPA_PLATFORM_VALUE"
  --setenv QT_WAYLAND_DISABLE_WINDOWDECORATIONS "$QT_WAYLAND_DISABLE_WINDOWDECORATIONS_VALUE"
  --setenv DBUS_SYSTEM_BUS_ADDRESS "$DBUS_SYSTEM_BUS_ADDRESS"
  --setenv DBUS_SESSION_BUS_ADDRESS "${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
  --setenv LIBSEAT_BACKEND "$LIBSEAT_BACKEND_VALUE"
  --setenv DESKTOP_TERMINAL_CMD "$TERMINAL_CMD"
  --setenv DESKTOP_BROWSER_FLATPAK_APP "$BROWSER_APP"
  --setenv DESKTOP_EDITOR_FLATPAK_APP "$EDITOR_APP"
  --setenv DESKTOPPAK_SESSION_LOG_FILE /run/desktoppak/logs/session.log
  --setenv DESKTOPPAK_SESSION_EXEC "$SESSION_EXEC"
  --unsetenv WAYLAND_DISPLAY
  --unsetenv DISPLAY
  --chdir /home/session
  /run/desktoppak/bin/desktoppak-session
)

bwrap "${BWRAP_ARGS[@]}"

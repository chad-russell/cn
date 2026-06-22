#!/usr/bin/env bash
set -euo pipefail

IMAGE="${NIRI_IMAGE:-localhost/niri-session:dev}"
TERMINAL_CMD="${DESKTOP_TERMINAL_CMD:-/usr/bin/ptyxis}"
BROWSER_APP="${DESKTOP_BROWSER_FLATPAK_APP:-app.zen_browser.zen}"
EDITOR_APP="${DESKTOP_EDITOR_FLATPAK_APP:-org.gnome.TextEditor}"
DBUS_SYSTEM_SOCKET="/run/dbus/system_bus_socket"
DBUS_SYSTEM_BUS_ADDRESS="unix:path=${DBUS_SYSTEM_SOCKET}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BLUEPRINT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/niri-bwrap-dev"
STATE_ROOT="${DESKTOP_BLUEPRINT_STATE_ROOT:-${DEFAULT_STATE_ROOT}}"
ROOTFS_DIR="${DESKTOP_BLUEPRINT_ROOTFS_DIR:-${BLUEPRINT_DIR}/state/rootfs}"
SESSION_ROOT="${STATE_ROOT}/session"
XDG_CONFIG_DIR="${DESKTOPPAK_CONFIG_ROOT:-${SESSION_ROOT}/xdg-config}"
XDG_STATE_DIR="${SESSION_ROOT}/xdg-state"
XDG_DATA_DIR="${SESSION_ROOT}/xdg-data"
XDG_CACHE_DIR="${SESSION_ROOT}/xdg-cache"
LOG_DIR="${SESSION_ROOT}/logs"

SESSION_HELPER="${SCRIPT_DIR}/bwrap-session.sh"
SESSION_SPAWN="${SCRIPT_DIR}/session-spawn.sh"
DEV_CONFIG_FILE="${DESKTOPPAK_DEV_CONFIG_FILE:-}"
PREPARE_ROOTFS="${SCRIPT_DIR}/prepare-rootfs.sh"
MANIFEST_REL="/usr/share/desktoppak/manifest.json"

: "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
LAUNCH_LOG="${XDG_RUNTIME_DIR}/niri-bwrap-launch.log"
exec >>"$LAUNCH_LOG" 2>&1

echo "=== $(date -Is) niri-bwrap launch ==="
echo "USER=${USER:-} HOME=${HOME:-} XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-}"
echo "SCRIPT_DIR=$SCRIPT_DIR"
echo "BLUEPRINT_DIR=$BLUEPRINT_DIR"
echo "STATE_ROOT=$STATE_ROOT"
echo "ROOTFS_DIR=$ROOTFS_DIR"

[ -d "$XDG_RUNTIME_DIR" ] || { echo "ERROR: XDG_RUNTIME_DIR missing: $XDG_RUNTIME_DIR"; exit 1; }
[ -S "$DBUS_SYSTEM_SOCKET" ] || { echo "ERROR: missing system bus socket: $DBUS_SYSTEM_SOCKET"; exit 1; }
command -v bwrap >/dev/null 2>&1 || { echo "ERROR: bwrap not found"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 not found"; exit 1; }

if [ ! -f "$ROOTFS_DIR$MANIFEST_REL" ]; then
  echo "Preparing rootfs from OCI image $IMAGE ..."
  "$PREPARE_ROOTFS" >/dev/null
fi

MANIFEST_PATH="${ROOTFS_DIR}${MANIFEST_REL}"
if [ ! -f "$MANIFEST_PATH" ]; then
  echo "ERROR: missing manifest at $MANIFEST_PATH"
  exit 1
fi

eval "$(python3 - "$MANIFEST_PATH" <<'PY'
import json, shlex, sys
p = sys.argv[1]
with open(p, 'r', encoding='utf-8') as f:
    m = json.load(f)
env = m.get('env', {})
seed = ''
seed_target = ''
for item in m.get('config', {}).get('seed', []):
    source = item.get('source')
    target = item.get('target')
    if source and target and target.startswith('/home/session/.config/'):
        seed = source
        seed_target = target
        break
pairs = {
    'SESSION_NAME': m.get('name', 'niri'),
    'DISPLAY_NAME': m.get('display_name', 'Niri (bubblewrap)'),
    'SESSION_EXEC': m.get('exec', '/usr/bin/niri'),
    'SESSION_DESKTOP': env.get('XDG_SESSION_DESKTOP', 'niri'),
    'CURRENT_DESKTOP': env.get('XDG_CURRENT_DESKTOP', 'niri'),
    'SESSION_TYPE': env.get('XDG_SESSION_TYPE', 'wayland'),
    'LIBSEAT_BACKEND_VALUE': env.get('LIBSEAT_BACKEND', 'logind'),
    'CONFIG_SEED_SOURCE': seed,
    'CONFIG_SEED_TARGET': seed_target,
}
for k, v in pairs.items():
    print(f'{k}={shlex.quote(v)}')
PY
)"

DEFAULT_CONFIG_SOURCE=""
CONFIG_SEED_HOST_TARGET=""
if [ -n "$CONFIG_SEED_SOURCE" ]; then
  DEFAULT_CONFIG_SOURCE="${ROOTFS_DIR}${CONFIG_SEED_SOURCE}"
fi
if [ -n "$CONFIG_SEED_TARGET" ]; then
  CONFIG_SEED_HOST_TARGET="${XDG_CONFIG_DIR}/${CONFIG_SEED_TARGET#/home/session/.config/}"
fi

mkdir -p \
  "$XDG_CONFIG_DIR" \
  "$XDG_STATE_DIR" \
  "$XDG_DATA_DIR" \
  "$XDG_CACHE_DIR" \
  "$LOG_DIR"

seed_source=""
if [ -n "$DEV_CONFIG_FILE" ] && [ -f "$DEV_CONFIG_FILE" ]; then
  seed_source="$DEV_CONFIG_FILE"
elif [ -n "$DEFAULT_CONFIG_SOURCE" ] && [ -f "$DEFAULT_CONFIG_SOURCE" ]; then
  seed_source="$DEFAULT_CONFIG_SOURCE"
fi

if [ -n "$CONFIG_SEED_HOST_TARGET" ]; then
  mkdir -p "$(dirname "$CONFIG_SEED_HOST_TARGET")"
fi

if [ "${NIRI_BWRAP_SYNC_CONFIG:-0}" = "1" ] || { [ -n "$CONFIG_SEED_HOST_TARGET" ] && [ ! -e "$CONFIG_SEED_HOST_TARGET" ]; }; then
  [ -n "$seed_source" ] || { echo "ERROR: no config seed source found"; exit 1; }
  [ -n "$CONFIG_SEED_HOST_TARGET" ] || { echo "ERROR: no config seed target found"; exit 1; }
  install -m 0644 "$seed_source" "$CONFIG_SEED_HOST_TARGET"
fi

[ -x "$ROOTFS_DIR$SESSION_EXEC" ] || { echo "ERROR: rootfs missing session exec at $ROOTFS_DIR$SESSION_EXEC"; exit 1; }

echo "Starting session"
echo "  name:         $SESSION_NAME"
echo "  display:      $DISPLAY_NAME"
echo "  exec:         $SESSION_EXEC"
echo "  image:        $IMAGE"
echo "  rootfs:       $ROOTFS_DIR"
echo "  state root:   $STATE_ROOT"
echo "  session root: $SESSION_ROOT"
echo "  runtime dir:  $XDG_RUNTIME_DIR"
echo "  session type: $SESSION_TYPE"
echo "  logs:         $LOG_DIR"
echo "  launch log:   $LAUNCH_LOG"

exec bwrap \
  --ro-bind "$ROOTFS_DIR" / \
  --dev-bind /dev /dev \
  --proc /proc \
  --ro-bind /sys /sys \
  --tmpfs /run \
  --dir /run/dbus \
  --dir /run/udev \
  --dir /run/systemd \
  --ro-bind-try /run/dbus /run/dbus \
  --ro-bind-try /run/udev /run/udev \
  --ro-bind-try /run/systemd /run/systemd \
  --bind "$XDG_RUNTIME_DIR" "$XDG_RUNTIME_DIR" \
  --tmpfs /tmp \
  --dir /run/desktop-blueprint \
  --dir /run/desktop-blueprint/bin \
  --tmpfs /home \
  --dir /home/session \
  --dir /home/session/.local \
  --bind "$XDG_CONFIG_DIR" /home/session/.config \
  --bind "$XDG_STATE_DIR" /home/session/.local/state \
  --bind "$XDG_DATA_DIR" /home/session/.local/share \
  --bind "$XDG_CACHE_DIR" /home/session/.cache \
  --bind "$LOG_DIR" /run/desktop-blueprint/logs \
  --ro-bind "$SESSION_HELPER" /run/desktop-blueprint/bin/desktop-blueprint-bwrap-session \
  --ro-bind "$SESSION_SPAWN" /run/desktop-blueprint/bin/session-spawn \
  --setenv HOME /home/session \
  --setenv USER "${USER:-user}" \
  --setenv LOGNAME "${LOGNAME:-${USER:-user}}" \
  --setenv SHELL /bin/bash \
  --setenv PATH "/run/desktop-blueprint/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  --setenv XDG_CONFIG_HOME /home/session/.config \
  --setenv XDG_STATE_HOME /home/session/.local/state \
  --setenv XDG_DATA_HOME /home/session/.local/share \
  --setenv XDG_CACHE_HOME /home/session/.cache \
  --setenv XDG_RUNTIME_DIR "$XDG_RUNTIME_DIR" \
  --setenv XDG_SESSION_ID "${XDG_SESSION_ID:-}" \
  --setenv XDG_SESSION_TYPE "$SESSION_TYPE" \
  --setenv XDG_SESSION_CLASS "${XDG_SESSION_CLASS:-user}" \
  --setenv XDG_SESSION_DESKTOP "$SESSION_DESKTOP" \
  --setenv XDG_CURRENT_DESKTOP "$CURRENT_DESKTOP" \
  --setenv XDG_SEAT "${XDG_SEAT:-seat0}" \
  --setenv XDG_VTNR "${XDG_VTNR:-}" \
  --setenv GDK_BACKEND wayland \
  --setenv QT_QPA_PLATFORM wayland \
  --setenv DBUS_SYSTEM_BUS_ADDRESS "$DBUS_SYSTEM_BUS_ADDRESS" \
  --setenv DBUS_SESSION_BUS_ADDRESS "${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}" \
  --setenv LIBSEAT_BACKEND "$LIBSEAT_BACKEND_VALUE" \
  --setenv DESKTOP_TERMINAL_CMD "$TERMINAL_CMD" \
  --setenv DESKTOP_BROWSER_FLATPAK_APP "$BROWSER_APP" \
  --setenv DESKTOP_EDITOR_FLATPAK_APP "$EDITOR_APP" \
  --setenv DESKTOP_SESSION_LOG_FILE /run/desktop-blueprint/logs/session.log \
  --setenv DESKTOPPAK_SESSION_EXEC "$SESSION_EXEC" \
  --unsetenv WAYLAND_DISPLAY \
  --unsetenv DISPLAY \
  --chdir /home/session \
  /run/desktop-blueprint/bin/desktop-blueprint-bwrap-session

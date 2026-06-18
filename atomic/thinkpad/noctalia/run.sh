#!/usr/bin/env bash
#
# Run `noctalia` inside a container, wired up to the host Wayland session.
#
# Persistent state is kept fully isolated from the host XDG_* tree: instead of
# bind-mounting ~/.config, ~/.cache, etc., all of Noctalia's state lives inside
# named Podman volumes (managed under Podman's volume store). Volumes are created
# automatically on first run; this script never touches their contents. To copy
# existing host data into them (a one-time step), use the separate seed.sh.
#
#   Manage the volumes with the usual podman commands, e.g.:
#     podman volume ls                                       # list
#     podman volume inspect noctalia-state                   # details / host path
#     podman volume export noctalia-state -o state.tar       # backup
#     podman volume rm noctalia-state                        # reset (destructive)
#
set -euo pipefail

IMAGE="${NOCTALIA_IMAGE:-noctalia}"
CT_NAME="${NOCTALIA_CONTAINER:-noctalia}"
CT_HOME=/home/noctalia

# --- Named volumes for isolated persistent state ------------------------------
#   "<volume-name>:<container-path>"
# All four Noctalia XDG subdirs are isolated volumes — even the ones that are
# empty on your host today — so nothing ever leaks into the host tree AND nothing
# Noctalia writes is lost on `podman rm`. Empty volumes cost nothing.
VOLUME_MOUNTS=(
  "noctalia-config:${CT_HOME}/.config/noctalia"
  "noctalia-state:${CT_HOME}/.local/state/noctalia"
  "noctalia-data:${CT_HOME}/.local/share/noctalia"
  "noctalia-cache:${CT_HOME}/.cache/noctalia"
)

# Seeding existing host data into these volumes is a one-time, manual step —
# see seed.sh. (This script only creates empty volumes and runs the app.)

# --- Host display environment --------------------------------------------------
: "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
: "${WAYLAND_DISPLAY:=wayland-0}"

WAYLAND_SOCKET="${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}"

if [[ ! -S "${WAYLAND_SOCKET}" ]]; then
  echo "ERROR: Wayland socket not found: ${WAYLAND_SOCKET}" >&2
  echo "       Run this from a Wayland session." >&2
  echo "       (XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR} WAYLAND_DISPLAY=${WAYLAND_DISPLAY})" >&2
  echo "       For an X11-only host, see the notes at the bottom of this script." >&2
  exit 1
fi

# --- GPU passthrough (skip if there is no /dev/dri, e.g. VMs) ------------------
# NOTE: for an NVIDIA host use CDI instead:  --device nvidia.com/gpu=all
DEVICE_ARGS=()
if [[ -e /dev/dri ]]; then
  DEVICE_ARGS+=(--device=/dev/dri)
fi

# --- Host system D-Bus (for NetworkManager, etc.) -----------------------------
# Noctalia's network panel reaches NetworkManager over the *system* D-Bus bus
# (org.freedesktop.NetworkManager), NOT the session bus. Forward the host's
# system bus socket so the name resolves; otherwise the panel reports
# "NetworkManager unavailable". No NetworkManager install is needed inside the
# container — Noctalia talks D-Bus directly. SELinux confinement is already
# disabled (--security-opt label=disable below), so the socket is reachable.
DBUS_SYSTEM_SOCKET="/run/dbus/system_bus_socket"
DBUS_ARGS=()
if [[ -S "${DBUS_SYSTEM_SOCKET}" ]]; then
  DBUS_ARGS+=(
    -v "${DBUS_SYSTEM_SOCKET}:${DBUS_SYSTEM_SOCKET}"
    -e "DBUS_SYSTEM_BUS_ADDRESS=unix:path=${DBUS_SYSTEM_SOCKET}"
  )
else
  echo "WARNING: system D-Bus socket not found (${DBUS_SYSTEM_SOCKET});" >&2
  echo "         the network panel will report 'NetworkManager unavailable'." >&2
fi

# --- Host timezone -------------------------------------------------------------
# Containers default to UTC; without this the clock/bar shows UTC time instead
# of local. Forward the host's /etc/localtime (the canonical Linux TZ file)
# read-only, and set TZ to the resolved zone name (e.g. America/New_York) for
# libraries (incl. Qt) that prefer the env var. Both are needed because some
# code reads one and some the other.
TZ_ARGS=()
if [[ -e /etc/localtime ]]; then
  TZ_ARGS+=(-v /etc/localtime:/etc/localtime:ro)
  # /etc/localtime is usually a symlink -> /usr/share/zoneinfo/<Name>; strip the
  # prefix to get the zone name. Falls back silently if it's a plain file copy.
  _zone="$(readlink -f /etc/localtime 2>/dev/null || true)"
  if [[ "${_zone}" == /usr/share/zoneinfo/* ]]; then
    TZ_ARGS+=(-e "TZ=${_zone#/usr/share/zoneinfo/}")
  fi
else
  echo "WARNING: /etc/localtime not found; the clock will default to UTC." >&2
fi

# --- systemd-logind session ---------------------------------------------------
# Noctalia reaches logind over the (already-forwarded) system D-Bus to change
# brightness, lock the session, and manage idle inhibit. The primary mechanism
# is Manager.GetSessionByPID(getpid()) — which a PID-namespaced container breaks
# (host logind returns NoSessionForPID for the container-local PID). The env-var
# fallback (GetSession($XDG_SESSION_ID)) resolves a *name* but logind still does
# not trust a PID-namespaced caller to actually act on that session, so
# Session.SetBrightness silently no-ops.
#
# Fix: --pid=host (see the podman run flags below). With the host PID namespace
# visible, GetSessionByPID returns noctalia's real host PID, which belongs to
# the user's logind session (podman was launched from it). logind then trusts
# the caller and writes the sysfs backlight itself, as root — no sysfs perms or
# udev rules needed. This matches the isolation model we agreed on: filesystem
# isolation (via volumes) is the goal; the PID namespace was never a real
# boundary for us (Noctalia previously ran as a plain niri process).
SESSION_ARGS=()
if [[ -n "${XDG_SESSION_ID:-}" ]]; then
  SESSION_ARGS+=(
    -e "XDG_SESSION_ID=${XDG_SESSION_ID}"
    -e "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-}"
    -e "XDG_SESSION_CLASS=${XDG_SESSION_CLASS:-}"
    -e "XDG_SESSION_DESKTOP=${XDG_SESSION_DESKTOP:-}"
    -e "XDG_SEAT=${XDG_SEAT:-seat0}"
    -e "XDG_VTNR=${XDG_VTNR:-}"
  )
else
  echo "WARNING: XDG_SESSION_ID is not set in the host environment." >&2
  echo "         logind-backed features (brightness keys, screen lock) will be limited." >&2
fi

# --- niri compositor IPC socket -----------------------------------------------
# Noctalia's brightness-up/down IPC (unlike the in-process slider) resolves the
# target backlights through the *compositor's* output set, not directly from
# /sys/class/backlight. For niri that means connecting to niri's IPC socket,
# whose path niri publishes in NIRI_SOCKET for processes it launches. The socket
# file already lives under XDG_RUNTIME_DIR (mounted above), so we only need to
# hand the path over as an env var — without it the compositor query returns an
# empty output list and brightness-up/down silently no-op (returns "ok", writes
# nothing, logs nothing).
COMPOSITOR_ARGS=()
if [[ -n "${NIRI_SOCKET:-}" ]]; then
  COMPOSITOR_ARGS+=(-e "NIRI_SOCKET=${NIRI_SOCKET}")
else
  echo "WARNING: NIRI_SOCKET is not set; brightness-up/down (and the F-keys) will" >&2
  echo "         silently no-op (the brightness slider will still work)." >&2
fi

# --- Ensure volumes exist -----------------------------------------------------
create_volumes() {
  for m in "${VOLUME_MOUNTS[@]}"; do
    local vol="${m%%:*}"
    podman volume create "$vol" >/dev/null 2>&1 || true
  done
}

create_volumes

# --- Fresh container, re-attaching the persistent volumes ----------------------
# `rm -f` removes only the container, never the named volumes, so state persists.
podman rm -f "${CT_NAME}" >/dev/null 2>&1 || true

VOL_ARGS=()
for m in "${VOLUME_MOUNTS[@]}"; do
  VOL_ARGS+=(-v "$m")
done

podman run -d \
  --name "${CT_NAME}" \
  --hostname "${CT_NAME}" \
  --userns=keep-id \
  --pid=host \
  --security-opt label=disable \
  --shm-size=2g \
  "${DEVICE_ARGS[@]}" \
  "${DBUS_ARGS[@]}" \
  "${TZ_ARGS[@]}" \
  "${SESSION_ARGS[@]}" \
  "${COMPOSITOR_ARGS[@]}" \
  "${VOL_ARGS[@]}" \
  -e WAYLAND_DISPLAY="${WAYLAND_DISPLAY}" \
  -e XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
  -e QT_QPA_PLATFORM=wayland \
  -e QT_WAYLAND_DISABLE_WINDOWDECORATIONS=1 \
  -e LANG=C.UTF-8 \
  -e XDG_DATA_DIRS="${XDG_DATA_DIRS}" \
  -e DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus" \
  -e HOME="${CT_HOME}" \
  -v "${XDG_RUNTIME_DIR}:${XDG_RUNTIME_DIR}" \
  "$IMAGE" \
  noctalia

echo
echo "Noctalia is running in container '${CT_NAME}'."
echo "  State (isolated, persistent):  $(printf '%s ' "${VOLUME_MOUNTS[@]}")"
echo "  Logs:        podman logs -f ${CT_NAME}"
echo "  Shell:       podman exec -it ${CT_NAME} sh"

#!/usr/bin/env bash
#
# ARCHIVED container-based Vicinae prototype.
# Current production path is host `vicinae` + `image/vicinae-bwrap`; see
# `vicinae/README.md`.
#
# Run `vicinae server` inside a container, wired up to the host Wayland session.
#
# After it is up, toggle the launcher with:
#
#     ./toggle.sh                     # == podman exec vicinae vicinae toggle
#
# Other handy commands:
#
#     podman logs -f vicinae          # follow server logs
#     podman exec -it vicinae bash    # shell inside the container
#     podman rm -f vicinae            # stop & remove
#
set -euo pipefail

IMAGE="${VICINAE_IMAGE:-localhost/vicinae:latest}"
CONTAINER="${VICINAE_CONTAINER:-vicinae}"

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

# --- Build the image if it isn't there yet ------------------------------------
if ! podman image exists "${IMAGE}"; then
  echo "Image ${IMAGE} not found; building..."
  podman build -t "${IMAGE}" -f Containerfile "$(dirname "$0")"
fi

# --- Persistent, writable HOME for vicinae inside the container ---------------
HOST_DATA="${HOME}/.local/share/vicinae-container"
mkdir -p "${HOST_DATA}"

# --- GPU passthrough (skip if there is no /dev/dri, e.g. VMs) ------------------
# NOTE: for an NVIDIA host use CDI instead:  --device nvidia.com/gpu=all
DEVICE_ARGS=()
if [[ -e /dev/dri ]]; then
  DEVICE_ARGS+=(--device=/dev/dri)
fi

# --- Qt rendering backend -----------------------------------------------------
# Default: QT_QUICK_BACKEND=software (CPU). This is the safe default -- it works
# without a working GL/EGL/Mesa stack in the container, which is the #1 reason
# GUI apps fail to render in containers. But it renders every frame on the CPU,
# which makes TOUCHPAD scrolling feel sluggish (a touchpad moves the list 1:1
# with your fingers, so every frame is on the hot path; a notched mouse wheel
# only redraws once per notch and is far less affected).
#
# To use the GPU (and get smooth touchpad scrolling), run:
#     VICINAE_USE_GPU=1 ./run.sh
# This OMITS QT_QUICK_BACKEND entirely, so Qt picks its default threaded OpenGL
# scenegraph. (You do NOT set QT_QUICK_BACKEND=gl -- the valid way to use the GPU
# is to leave it unset; "software" is the only software value.) Requires the
# --device=/dev/dri passthrough above + a matching Mesa stack in the image.
QT_BACKEND_ARGS=(-e QT_QUICK_BACKEND=software)
if [[ "${VICINAE_USE_GPU:-}" == "1" ]]; then
  QT_BACKEND_ARGS=()
fi

# --- App discovery: surface host .desktop files, icons & flatpaks --------------
# vicinae discovers launchable apps from <XDG_DATA_DIRS>/applications/*.desktop.
# The container ships its own (nearly empty) /usr/share, so we bind-mount the
# host's app/icon directories read-only and point XDG_DATA_DIRS at them.
#
# System dirs are mounted at their *original* paths so that absolute icon paths
# referenced inside .desktop files still resolve.
HOST_HOME="${HOME}"
APP_MOUNTS=()
for d in \
  /usr/share/applications \
  /usr/share/icons \
  /usr/share/pixmaps \
  /usr/local/share/applications \
  /usr/local/share/icons \
  ; do
  [[ -e "${d}" ]] && APP_MOUNTS+=("-v" "${d}:${d}:ro")
done

# Flatpak. We mount the ENTIRE flatpak tree, not just exports/share, because the
# files under .../exports/share/{applications,icons}/*.desktop are SYMLINKS into
# .../app/<id>/<arch>/<branch>/<commit>/export/share/... (and .../files/share/...
# for icons). Mounting only exports/share left those symlinks DANGLING, so
# vicinae's is_regular_file() check (which follows symlinks) returned false and
# every flatpak was silently dropped during scan. Mounting the whole tree makes
# the symlink targets resolve -- fixing both app discovery AND flatpak icons.
for d in \
  /var/lib/flatpak \
  "${HOST_HOME}/.local/share/flatpak" \
  ; do
  [[ -e "${d}" ]] && APP_MOUNTS+=("-v" "${d}:${d}:ro")
done

# Per-user .desktop files / icons: expose under a synthetic share root so the
# applications/ + icons/ layout that XDG expects is preserved.
[[ -e "${HOST_HOME}/.local/share/applications" ]] && \
  APP_MOUNTS+=("-v" "${HOST_HOME}/.local/share/applications:/host-user-share/applications:ro")
[[ -e "${HOST_HOME}/.local/share/icons" ]] && \
  APP_MOUNTS+=("-v" "${HOST_HOME}/.local/share/icons:/host-user-share/icons:ro")

# Order: user overrides first, then user flatpak, system flatpak, then system.
XDG_DATA_DIRS="/host-user-share:${HOST_HOME}/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share"

# Fresh start each invocation.
podman rm -f "${CONTAINER}" >/dev/null 2>&1 || true

echo "Starting vicinae server in container '${CONTAINER}'..."
podman run -d \
  --name "${CONTAINER}" \
  --hostname vicinae \
  --userns=keep-id \
  --security-opt label=disable \
  --shm-size=2g \
  "${DEVICE_ARGS[@]}" \
  "${APP_MOUNTS[@]}" \
  "${QT_BACKEND_ARGS[@]}" \
  -e WAYLAND_DISPLAY="${WAYLAND_DISPLAY}" \
  -e XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
  -e QT_QPA_PLATFORM=wayland \
  -e QT_WAYLAND_DISABLE_WINDOWDECORATIONS=1 \
  -e LANG=C.UTF-8 \
  -e XDG_DATA_DIRS="${XDG_DATA_DIRS}" \
  -e DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus" \
  -e HOME=/home/vicinae \
  -e XDG_CONFIG_HOME=/home/vicinae/.config \
  -e XDG_DATA_HOME=/home/vicinae/.local/share \
  -v "${XDG_RUNTIME_DIR}:${XDG_RUNTIME_DIR}" \
  -v "${HOST_DATA}:/home/vicinae" \
  "${IMAGE}" \
  vicinae server

echo
echo "Server started. Now try:  ./toggle.sh"
echo
# Notes:
#   * QT_QUICK_BACKEND=software avoids needing a working GL/EGL stack, which is
#     the most common reason GUI apps fail to render in a container. It uses more
#     CPU but a launcher is mostly idle, so it's a safe default. To use the GPU,
#     drop that line and make sure --device=/dev/dri + a matching Mesa stack work.
#   * --userns=keep-id makes the container run as your host UID, so the Wayland
#     socket (mode 700, owned by you) is reachable and vicinae can write its own
#     IPC socket into XDG_RUNTIME_DIR -- which is also how `vicinae toggle` finds
#     the server.
#   * --security-opt label=disable turns off SELinux confinement so the container
#     can reach the host Wayland/GPU device files (Fedora runs SELinux enforcing).
#   * We bind the whole $XDG_RUNTIME_DIR so the server can create its IPC socket
#     where `vicinae toggle` (run via `podman exec`) will look for it. The exec'd
#     process inherits these same env vars, so discovery is identical.
#   * X11-only host: instead of WAYLAND_DISPLAY, pass -e DISPLAY=$DISPLAY plus
#     `xhost +SI:localuser:$(whoami)` and mount /tmp/.X11-unix. The rest stays.

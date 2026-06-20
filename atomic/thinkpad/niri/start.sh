#!/bin/sh
# Launch the full niri + Noctalia desktop in a throwaway podman container.
#
# Run this FROM A FREE VT: Ctrl+Alt+F3, log in as your user, then ./start.sh.
# The container exits when niri exits (--rm cleans it up). Nothing on the host
# is touched except the shared /run/user/$UID runtime dir (same as toolbox).
#
# -----------------------------------------------------------------------------
# Architecture: seatd AS ROOT, niri + clients AS THE USER
# -----------------------------------------------------------------------------
# Two different uids run inside one container, by design:
#
#   seatd  -> runs as ROOT (uid 0). Only root can become DRM master and open
#             /dev/input event nodes. seatd acquires the seat, then hands the
#             DRM + input fds to clients over a unix socket.
#
#   niri   -> runs AS THE REAL USER (uid 1000) via `setpriv`. It connects to
#             seatd's socket (LIBSEAT_BACKEND=seatd) and gets the fds. Everything
#             niri spawns (Noctalia, alacritty, fuzzel) inherits uid 1000.
#
# Why split it like this instead of the old "everything as root":
#
#   PipeWire authenticates clients by uid. The host pipewire-0 socket belongs to
#   uid 1000; a root Noctalia connecting to it is REJECTED — that is exactly why
#   audio never worked before. A uid-1000 Noctalia connects fine. (Root could
#   never have fixed this; the runtime-dir theory was a red herring.)
#
#   logind SetBrightness (the path brightnessctl falls back to when /sys is
#   read-only) trusts the session OWNER. uid 1000 owns session c4, so it works;
#   root does not own it, so it would not.
#
# Why seatd and not logind's own backend: niri's libseat logind backend fails
# to take the session controller from inside a container ("Failed to open
# session: Function not implemented" / ENOSYS) because logind's TakeControl
# handoff doesn't survive the namespace split cleanly. seatd sidesteps logind
# for the *seat* (DRM/input) entirely — it takes them as root — while logind is
# still reached over the forwarded system bus for the things that genuinely
# need it (brightness), by the uid-1000 clients.
#
# -----------------------------------------------------------------------------
# Why logout no longer locks up
# -----------------------------------------------------------------------------
# The black-screen-on-quit lockup was seatd being SIGKILLed by podman teardown
# while it still held the VT in KD_GRAPHICS, so nothing restored the text
# console. Now the session wrapper runs niri in the FOREGROUND and installs an
# EXIT trap that sends seatd SIGTERM and waits for it: seatd runs its VT
# restore path (KD_TEXT, release master) BEFORE the container dies. Normal
# logout (Mod+Shift+E / niri crash / Ctrl+C) all flows through that trap.
#
# Host integration the container reproduces (the toolbox/distrobx recipe, see
# toolbox/src/cmd/create.go and bxt.rs "Using Fedora Silverblue for Compositor
# Development"):
#   --pid host        so logind's sd_pid_get_session() resolves the caller
#   --cgroupns host   so the caller's cgroup matches its logind session
#   /run/dbus/system_bus_socket  forwarded -> logind for SetBrightness
#   /run/user/$UID    forwarded at the SAME path -> PipeWire + Wayland sockets
# -----------------------------------------------------------------------------
set -e

IMAGE="${NIRI_IMAGE:-localhost/niri-dev:latest}"
LOG="niri-session.log"
DBUS_SYSTEM_SOCKET="/run/dbus/system_bus_socket"
DBUS_SYSTEM_BUS_ADDRESS="unix:path=${DBUS_SYSTEM_SOCKET}"

# --- sanity: must be a real text-VT logind session ----------------------------
if [ -z "${XDG_SESSION_ID:-}" ]; then
    cat >&2 <<'EOF'
ERROR: XDG_SESSION_ID is not set.
       Switch to a free VT (Ctrl+Alt+F3), log in as your user, and run
       ./start.sh FROM THAT login shell — not over SSH and not under `sudo`.
       (The script itself uses `sudo` for the rootful podman call.)
EOF
    exit 1
fi
if [ "${XDG_SESSION_TYPE:-}" != "tty" ]; then
    echo "WARNING: XDG_SESSION_TYPE='${XDG_SESSION_TYPE:-}' (expected 'tty')." >&2
    echo "         You probably want a free VT (Ctrl+Alt+F3), not a GNOME terminal." >&2
    echo "         Continuing in 3s..." >&2
    sleep 3
fi
[ -S "$DBUS_SYSTEM_SOCKET" ] || {
    echo "ERROR: system D-Bus socket not found at $DBUS_SYSTEM_SOCKET" >&2
    echo "       logind brightness (and clean seat handoff) cannot work without it." >&2
    exit 1
}

: "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
[ -d "$XDG_RUNTIME_DIR" ] || {
    echo "ERROR: XDG_RUNTIME_DIR ($XDG_RUNTIME_DIR) does not exist." >&2
    exit 1
}

# Capture the REAL user identity before `sudo`. These are what niri/Noctalia
# will run as inside the container (so they match the host PipeWire daemon and
# the logind session owner).
HOST_UID=$(id -u)
HOST_GID=$(id -g)

echo "Starting niri + Noctalia.  Log: $LOG"
echo "  session:     $XDG_SESSION_ID  (VT ${XDG_VTNR:-?}, seat ${XDG_SEAT:-?})"
echo "  compositor:  seatd(root) -> niri(uid $HOST_UID)"
echo "  runtime dir: $XDG_RUNTIME_DIR   (PipeWire + Wayland sockets)"
echo "  system bus:  $DBUS_SYSTEM_SOCKET   (logind brightness)"
echo
echo "Return to GNOME: Ctrl+Alt+F2.  Stop niri: Ctrl+C here, or Mod+Shift+E."
echo

# NOTE: the $HOST_UID etc. below expand in THIS shell (the user's VT login
# shell) before sudo runs podman, so the real session identity is carried in.
# The image's /usr/local/bin/niri-container-session helper runs as root (so
# seatd can be root), then uses setpriv to drop niri + everything it spawns to
# uid $HOST_UID.
sudo podman run --rm -it \
    --name niri-dev-session \
    --privileged \
    --user 0:0 \
    --userns host \
    --pid host \
    --cgroupns host \
    --ipc host \
    --network host \
    --security-opt label=disable \
    --ulimit host \
    -v /dev:/dev:rslave \
    -v /sys:/sys:ro \
    -v /run/udev:/run/udev:ro \
    -v "${DBUS_SYSTEM_SOCKET}:${DBUS_SYSTEM_SOCKET}" \
    -v "${XDG_RUNTIME_DIR}:${XDG_RUNTIME_DIR}" \
    -v /etc/localtime:/etc/localtime:ro \
    -e HOST_UID="$HOST_UID" \
    -e HOST_GID="$HOST_GID" \
    -e DBUS_SYSTEM_BUS_ADDRESS="$DBUS_SYSTEM_BUS_ADDRESS" \
    -e HOME=/tmp/niri-home \
    -e XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    -e XDG_SESSION_ID="$XDG_SESSION_ID" \
    -e XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-tty}" \
    -e XDG_SESSION_CLASS="${XDG_SESSION_CLASS:-user}" \
    -e XDG_SESSION_DESKTOP="niri" \
    -e XDG_SEAT="${XDG_SEAT:-seat0}" \
    -e XDG_VTNR="${XDG_VTNR:-}" \
    -e XDG_CURRENT_DESKTOP="niri" \
    -e GDK_BACKEND=wayland \
    -e QT_QPA_PLATFORM=wayland \
    "$IMAGE" /usr/local/bin/niri-container-session 2>&1 | tee "$LOG"

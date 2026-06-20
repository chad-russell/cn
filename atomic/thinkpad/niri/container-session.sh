#!/bin/sh
# Container-side session wrapper for the niri desktop.
# Runs seatd as root, then drops to the real host uid/gid for niri + clients.

set -eu

: "${HOST_UID:?HOST_UID must be set}"
: "${HOST_GID:?HOST_GID must be set}"
: "${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR must be set}"
: "${XDG_SESSION_ID:?XDG_SESSION_ID must be set}"

runtime="$XDG_RUNTIME_DIR"
home_dir="${HOME:-/tmp/niri-home}"
session_type="${XDG_SESSION_TYPE:-tty}"
session_class="${XDG_SESSION_CLASS:-user}"
session_desktop="${XDG_SESSION_DESKTOP:-niri}"
seat_name="${XDG_SEAT:-seat0}"
vt_number="${XDG_VTNR:-}"
current_desktop="${XDG_CURRENT_DESKTOP:-niri}"
system_bus_address="${DBUS_SYSTEM_BUS_ADDRESS:-unix:path=/run/dbus/system_bus_socket}"
seatd_log=/tmp/seatd.log
session_pid=

mkdir -p "$runtime" "$home_dir/Pictures/Screenshots"
chown -h "$HOST_UID:$HOST_GID" "$runtime" 2>/dev/null || true
chmod 700 "$runtime" 2>/dev/null || true

# dbus-daemon wants passwd/group resolution for the uid it runs as. Since we
# drop to the host uid/gid with setpriv, make sure that identity exists inside
# the container even if the image has no matching user entry.
if ! getent group "$HOST_GID" >/dev/null 2>&1; then
    echo "hostuser:x:$HOST_GID:" >> /etc/group
fi
if ! getent passwd "$HOST_UID" >/dev/null 2>&1; then
    echo "hostuser:x:$HOST_UID:$HOST_GID:Container session user:$home_dir:/bin/sh" >> /etc/passwd
fi

export SEATD_SOCK=/run/seatd.sock
rm -f "$SEATD_SOCK"

# Stick to seatd's default socket path for compatibility across seatd versions;
# the Fedora build in your log rejects the old custom-socket flag.
seatd -l info >"$seatd_log" 2>&1 &
seatd_pid=$!

i=0
while [ "$i" -lt 50 ] && [ ! -S "$SEATD_SOCK" ]; do
    i=$((i + 1))
    sleep 0.1
done

if [ ! -S "$SEATD_SOCK" ]; then
    echo "!! seatd did not create $SEATD_SOCK; see $seatd_log:" >&2
    cat "$seatd_log" >&2 || true
    kill "$seatd_pid" 2>/dev/null || true
    exit 1
fi

chmod 666 "$SEATD_SOCK" 2>/dev/null || true

cleanup() {
    if [ -n "${session_pid:-}" ]; then
        kill -TERM "$session_pid" 2>/dev/null || true
        wait "$session_pid" 2>/dev/null || true
    fi

    kill -TERM "$seatd_pid" 2>/dev/null || true
    wait "$seatd_pid" 2>/dev/null || true
    rm -f "$SEATD_SOCK"
}

trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

setpriv --reuid "$HOST_UID" --regid "$HOST_GID" --clear-groups -- \
    env \
        HOME="$home_dir" \
        XDG_RUNTIME_DIR="$runtime" \
        XDG_SESSION_ID="$XDG_SESSION_ID" \
        XDG_SESSION_TYPE="$session_type" \
        XDG_SESSION_CLASS="$session_class" \
        XDG_SESSION_DESKTOP="$session_desktop" \
        XDG_SEAT="$seat_name" \
        XDG_VTNR="$vt_number" \
        XDG_CURRENT_DESKTOP="$current_desktop" \
        GDK_BACKEND=wayland \
        QT_QPA_PLATFORM=wayland \
        DBUS_SYSTEM_BUS_ADDRESS="$system_bus_address" \
        SEATD_SOCK="$SEATD_SOCK" \
        LIBSEAT_BACKEND=seatd \
        dbus-run-session -- niri --session &
session_pid=$!

if wait "$session_pid"; then
    session_status=0
else
    session_status=$?
fi

session_pid=
exit "$session_status"

#!/bin/sh
# Launch the full COSMIC desktop in a temporary container.
#
# Run this FROM A FREE VT (Ctrl+Alt+F3), after logging in as your user.
# The container exits when the desktop exits, and --rm cleans it up.

set -e

IMAGE=localhost/cosmic-dev:latest
LOG=cosmic-session.log

echo "Starting COSMIC session. Log: $LOG"
echo "To return to GNOME: Ctrl+Alt+F2. To stop COSMIC: Ctrl+C here."
echo

sudo podman run --rm -it \
    --name cosmic-dev-session \
    --privileged --network=host \
    --device /dev/dri --device /dev/input --device /dev/tty \
    -v /run/udev:/run/udev:ro \
    -e LIBSEAT_BACKEND=seatd \
    -e XDG_RUNTIME_DIR=/run/xdg \
    -e XDG_CURRENT_DESKTOP=COSMIC \
    -e XDG_SESSION_DESKTOP=COSMIC \
    -e XDG_SESSION_TYPE=wayland \
    -e DCONF_PROFILE=/usr/share/dconf/profile/cosmic \
    -e GDK_BACKEND=wayland,x11 \
    -e QT_QPA_PLATFORM=wayland \
    "$IMAGE" sh -lc '
        mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix
        pkill -x seatd 2>/dev/null || true
        nohup seatd -l info >/tmp/seatd.log 2>&1 &
        exec dbus-run-session -- cosmic-session
    ' 2>&1 | tee "$LOG"

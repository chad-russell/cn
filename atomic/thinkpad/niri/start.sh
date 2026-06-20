#!/bin/sh
# Launch the full niri + Noctalia desktop in a temporary container.
#
# Run this FROM A FREE VT (Ctrl+Alt+F3), after logging in as your user.
# The container exits when niri exits, and --rm cleans it up. Nothing on the
# host is touched: the config, home, and runtime all live inside the container.

set -e

IMAGE=localhost/niri-dev:latest
LOG=niri-session.log

echo "Starting niri + Noctalia session. Log: $LOG"
echo "To return to GNOME: Ctrl+Alt+F2. To stop niri: Ctrl+C here (or Mod+Shift+E)."
echo

sudo podman run --rm -it \
    --name niri-dev-session \
    --privileged \
    --network=host \
    --ipc=host \
    --device /dev/dri --device /dev/input --device /dev/tty \
    -v /run/udev:/run/udev:ro \
    -v /dev:/dev \
    -e LIBSEAT_BACKEND=seatd \
    -e XDG_RUNTIME_DIR=/run/xdg \
    -e XDG_CURRENT_DESKTOP=niri \
    -e XDG_SESSION_DESKTOP=niri \
    -e XDG_SESSION_TYPE=wayland \
    -e GDK_BACKEND=wayland \
    -e QT_QPA_PLATFORM=wayland \
    "$IMAGE" sh -lc '
        mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
        mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix
        pkill -x seatd 2>/dev/null || true
        nohup seatd -l info >/tmp/seatd.log 2>&1 &
        # --session imports niri env into the D-Bus activation environment and
        # starts its D-Bus services; it works fine without systemd here because
        # dbus-run-session provides the session bus.
        exec dbus-run-session -- niri --session
    ' 2>&1 | tee "$LOG"

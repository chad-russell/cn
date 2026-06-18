# noctalia (containerized)

Runs [Noctalia](https://docs.noctalia.dev/) v5 inside a Podman container wired to
the host Wayland session. State is held in isolated Podman volumes, not bind
mounted from the host tree.

## Build & run

```bash
podman build -t noctalia .
./run.sh
```

`run.sh` recreates the container from the image on each run, so rebuild the
image whenever you change the `Containerfile` or `noctalia-brightness`, then run
the script again.

```bash
podman logs -f noctalia          # logs
podman exec -it noctalia sh      # shell
```

## Brightness keys (host niri config)

Noctalia's own `brightness-up`/`brightness-down` IPC and OSD **don't work inside
the container**: the inotify watch it places on the backlight sysfs file doesn't
deliver events, so its cached brightness freezes at the startup value. Relative
commands then apply `(startup_value ± step)` and never show an OSD. (Absolute
`brightness-set <value>` does change the hardware, but still no OSD.)

The fix is a tiny helper baked into the image (`/usr/local/bin/noctalia-brightness`)
that drives the backlight with `brightnessctl` and then shows the OSD explicitly.
Add this to your `~/.config/niri/config.kdl`:

```kdl
binds {
    XF86MonBrightnessUp   { spawn-sh "podman exec noctalia noctalia-brightness up"; }
    XF86MonBrightnessDown { spawn-sh "podman exec noctalia noctalia-brightness down"; }
}
```

Both lines accept an optional step (percentage points), defaulting to 5:

```kdl
    XF86MonBrightnessUp { spawn-sh "podman exec noctalia noctalia-brightness up 10"; }
```

Volume keys need no special handling — `noctalia msg volume-up/down/mute` work
unchanged and already show the OSD, so bind those directly as usual.

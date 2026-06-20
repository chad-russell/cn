# niri-dev

Bleeding-edge **niri** (git nightly) + **Noctalia v5** shell, running fully
inside a throwaway podman container — nothing leaks to the host. Mirrors the
`../cosmic/` workflow but for niri.

## How it works: seatd AS ROOT, niri + clients AS THE USER

Two different uids run inside one container, by design:

```
   seatd (root)  ──acquires──►  DRM master + /dev/input + VT
        │
        │ (hands fds over /run/seatd.sock)
        ▼
   niri (uid 1000) ──spawns──► Noctalia, alacritty, fuzzel  (all uid 1000)
        │
        ├── /run/user/1000/pipewire-0  ──► host PipeWire  (uid matches ✓)
        └── /run/dbus/system_bus_socket ──► logind SetBrightness  (session owner ✓)
```

- **seatd as root** is the only thing that can become DRM master and open input
  devices. It takes the seat, then passes the DRM + input fds to clients over a
  unix socket (`/run/seatd.sock`).
- **niri + everything it spawns runs as the real user (uid 1000)** via `setpriv`.

### Why the split (this is the core of every fix)

| Thing that was broken | Why it was broken | Why the split fixes it |
|---|---|---|
| **Logout → black screen / lockup** | `seatd` was detached via `nohup &` and got SIGKILLed by podman teardown while it still held the VT in `KD_GRAPHICS`, so the text console was never restored. | niri now runs in the foreground with an **EXIT trap that SIGTERMs seatd and waits** — seatd runs its VT-restore path (`KD_TEXT`, drop master) *before* the container dies. |
| **No audio / "PipeWire unavailable"** | Everything ran as **root**. PipeWire authenticates clients by uid; the host `pipewire-0` socket belongs to uid 1000, so a root Noctalia connecting to it was **rejected**. | Noctalia now runs as **uid 1000**, matching the host PipeWire daemon. (The runtime-dir theory was a red herring — the uid mismatch was the real cause.) |
| **Volume / brightness keys dead** | No system bus for brightness; volume had no PipeWire; Noctalia's brightness cache froze (sysfs inotify doesn't fire in a container). | PipeWire now reachable (uid match); system bus forwarded; brightness via the baked `niri-brightness` helper (`brightnessctl` → logind `SetBrightness` over the forwarded system bus as the session owner, then Noctalia OSD). |

### Why seatd, and not logind's own seat backend?

We tried niri's libseat **logind** backend (run niri as the user, let logind
hand it the DRM/input fds). It fails inside a container with
`Failed to open session: Function not implemented (os error 38)` (ENOSYS) —
logind's `TakeControl` seat-controller handoff doesn't survive the namespace
split cleanly. seatd sidesteps logind for the *seat* entirely (it takes DRM
master as root), while logind is still reached over the forwarded system bus —
by the uid-1000 clients — for the one thing that genuinely needs it (brightness).

The host integration the container reproduces is the **toolbox/distrobx recipe**
(`toolbox/src/cmd/create.go`): `--pid host` + `--cgroupns host` so logind's
`sd_pid_get_session()` resolves the caller, plus the system bus socket and the
real `/run/user/$UID` forwarded at the same path. See
[bxt.rs — Using Fedora Silverblue for Compositor Development][bxt] and
[containertoolbx.org — Wayland Session][toolbx].

[bxt]: https://bxt.rs/blog/using-fedora-silverblue-for-compositor-development/
[toolbx]: https://containertoolbx.org/use/#wayland-session

## What's in the image

| Piece          | Source                                                    |
|----------------|-----------------------------------------------------------|
| niri           | `yalter/niri-git` COPR (git/nightly builds)               |
| Noctalia v5    | `noctalia-git` from the `lionheartp/Hyprland` COPR        |
| seat broker    | `seatd` (runs as root inside the container)               |
| session bus    | `dbus-daemon` (provides `dbus-run-session`, no systemd)   |
| backlight keys | `brightnessctl` + baked `niri-brightness` helper          |
| terminal       | `alacritty`                                               |
| launcher       | `fuzzel`                                                   |

Base image is the same local `localhost/cdev:latest` (Fedora) the cosmic image
uses, so the GL/DRI stack is already present.

A working niri config is baked in at `/etc/niri/config.kdl` (niri's system-wide
fallback). It autostarts Noctalia, sets up rounded corners, and wires up
Noctalia's key binds. Because it lives in the image, **nothing is written to
your host** (the shared `/run/user/$UID` is the only host path touched, same as
toolbox).

## Workflow

```sh
./build.sh     # build the image from Containerfile (first time, or after edits)
./start.sh     # run the desktop in a temporary container — run from a free VT!
./update.sh    # dnf update inside a temp container + commit back (no full rebuild)
```

`update.sh` refreshes the niri/noctalia packages to the newest COPR builds
without rebuilding from scratch. After editing `Containerfile`,
`niri-brightness`, or `config.kdl`, re-run `./build.sh`.

## Running it

1. Switch to a free VT: **Ctrl+Alt+F3**, log in as your user.
2. `cd` here and run `./start.sh`.
3. niri comes up with Noctalia. Return to GNOME with **Ctrl+Alt+F2**; stop niri
   with **Ctrl+C** in the VT, or **Mod+Shift+E** in the session.

`start.sh` sanity-checks that you're in a real logind `tty` session and that the
system bus + runtime dir are reachable; it refuses to start otherwise (running
it from inside GNOME would try to share the seat with GNOME). Nothing else on
the host changes — the container is `--rm` and `$HOME` is a tmpfs.

## Key binds (Mod = Super on a TTY)

- `Mod+T` terminal · `Mod+D` launcher
- `Mod+Space` Noctalia launcher · `Mod+S` control center · `Mod+Comma` settings
- `Mod+O` overview · `Mod+Q` close · `Mod+Shift+E` exit
- Focus/move with `H J K L` / arrows, workspaces `Mod+U`/`Mod+I` or `Mod+1–9`
- Volume keys → Noctalia→PipeWire; brightness keys → `niri-brightness` (logind)

Full set is in `config.kdl`. The config is live-reloaded — edit and save; or run
`niri validate` (inside the container) to check it.

## How volume / brightness actually get to hardware

```
volume keys  ─► noctalia msg volume-* ─► PipeWire (host /run/user/$UID/pipewire-0)
brightness   ─► niri-brightness ─► brightnessctl ─► logind Session.SetBrightness
                                                └─► noctalia msg brightness-osd
```

- **Volume**: Noctalia (uid 1000) talks to the host PipeWire socket directly —
  the uid now matches, so the connection is accepted.
- **Brightness**: `noctalia msg brightness-up/down` would freeze in a container
  (Noctalia's brightness cache is refreshed by an inotify watch on the backlight
  sysfs file, and sysfs inotify doesn't deliver inside a container — same reason
  `../noctalia/noctalia-brightness` exists). `niri-brightness` sidesteps it:
  `brightnessctl` calls logind `SetBrightness` over the forwarded system bus as
  the session owner (uid 1000), then pokes Noctalia's OSD with the absolute
  value. Set `NOCTALIA_BRIGHTNESS_DEBUG=1` to trace it.

## Notes / gotchas

- **Run from a free VT.** `start.sh` checks `XDG_SESSION_TYPE=tty`. Run it from
  the VT login shell directly (it `sudo`s itself for the rootful podman call).
- **Logout is clean now.** Exiting niri (Ctrl+C, `Mod+Shift+E`, or a crash)
  flows through the EXIT trap, which SIGTERMs seatd so it restores the VT before
  the container is removed. The old `nohup seatd &` path left the VT wedged in
  `KD_GRAPHICS` → black screen + reboot.
- niri's `--session` imports its environment into the D-Bus activation
  environment and starts its D-Bus services; it works here because
  `dbus-run-session` supplies a fresh session bus (no systemd needed). The
  system bus — logind — is the forwarded host one.
- X11 apps need Xwayland, which is intentionally **not** included. Everything
  shipped here (alacritty, fuzzel, Noctalia) is Wayland-native.
- If you get a black screen on *startup*, the most likely cause is the DRI/GPU
  stack — the base `cdev` image is expected to provide it (same as cosmic).

## Troubleshooting

- **`Failed to open session: Function not implemented (os error 38)`** — niri's
  libseat fell through to its builtin backend, which can't acquire DRM master.
  This means it did NOT connect to seatd. Check `/tmp/seatd.log` (inside the
  container, captured to the session log): seatd must have created
  `/run/seatd.sock` and opened the DRM node. The fix is `LIBSEAT_BACKEND=seatd`
  + `SEATD_SOCK` pointing at it (both set by `start.sh`) and seatd running as
  root.
- **`XDG_SESSION_ID is not set`** — you ran `start.sh` from somewhere that isn't
  a text-VT login shell (over SSH, or `sudo ./start.sh`). Switch to
  Ctrl+Alt+F3, log in, and run `./start.sh` directly.
- **Audio still missing** — confirm Noctalia is running as uid 1000 (`ps -o
  uid=,pid=,comm= -C noctalia` should show uid 1000, not 0) and that the host
  PipeWire socket exists at `/run/user/$UID/pipewire-0`.
- **Brightness changes but no OSD** — Noctalia's IPC socket isn't reachable from
  the spawned `niri-brightness`. Check that Noctalia started and that
  `XDG_RUNTIME_DIR` is the real `/run/user/$UID`.
- **Still locks up on exit** — a SIGKILL (kill -9, OOM) bypasses the EXIT trap.
  Use Ctrl+C or `Mod+Shift+E` for a clean teardown that lets seatd restore the
  VT. If even clean exit wedges the VT, `sudo systemctl restart systemd-logind`
  or switch VTs (`chvt 2`) recovers it without a reboot.

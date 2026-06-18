# niri-dev

Bleeding-edge **niri** (git nightly) + **Noctalia v5** shell, running fully
inside a throwaway podman container — nothing leaks to the host. Mirrors the
`../cosmic/` workflow but for niri.

## What's in the image

| Piece          | Source                                                    |
|----------------|-----------------------------------------------------------|
| niri           | `yalter/niri-git` COPR (git/nightly builds)               |
| Noctalia v5    | `noctalia-git` from the `lionheartp/Hyprland` COPR        |
| session bus    | `dbus-daemon` (provides `dbus-run-session`, no systemd)   |
| seat management| `seatd` (via `LIBSEAT_BACKEND=seatd`, no logind)          |
| terminal       | `alacritty`                                               |
| launcher       | `fuzzel`                                                   |

Base image is the same local `localhost/cdev:latest` (Fedora) the cosmic image
uses, so the GL/DRI stack is already present.

A working niri config is baked in at `/etc/niri/config.kdl` (niri's system-wide
fallback). It autostarts Noctalia, sets up rounded corners, and wires up
Noctalia's key binds. Because it lives in the image, **nothing is written to
your host**.

## Workflow

```sh
./build.sh     # build the image from Containerfile (first time, or after edits)
./start.sh     # run the desktop in a temporary container — run from a free VT!
./update.sh    # dnf update inside a temp container + commit back (no full rebuild)
```

`update.sh` is the "update without rebuilding the world" path: it refreshes the
niri/noctalia packages to the newest COPR builds and saves them into the image.

## Running it

1. Switch to a free VT: **Ctrl+Alt+F3**, log in as your user.
2. `cd` here and run `./start.sh`.
3. niri comes up with Noctalia. Return to GNOME with **Ctrl+Alt+F2**; stop niri
   with **Ctrl+C** in the VT, or **Mod+Shift+E** in the session.

Nothing on the host changes — the container is `--rm`, the home dir and config
are all inside it.

## Key binds (Mod = Super on a TTY)

- `Mod+T` terminal · `Mod+D` launcher
- `Mod+Space` Noctalia launcher · `Mod+S` control center · `Mod+Comma` settings
- `Mod+O` overview · `Mod+Q` close · `Mod+Shift+E` exit
- Focus/move with `H J K L` / arrows, workspaces `Mod+U`/`Mod+I` or `Mod+1–9`
- Volume/brightness keys are routed through Noctalia (keeps its OSD in sync)

Full set is in `config.kdl`. The config is live-reloaded — edit and save; or run
`niri validate` (inside the container) to check it.

## Notes / gotchas

- niri's `--session` imports its environment into the D-Bus activation
  environment and starts its D-Bus services; it works here because
  `dbus-run-session` supplies the session bus (no systemd needed).
- X11 apps need Xwayland, which is intentionally **not** included. Everything
  shipped here (alacritty, fuzzel, Noctalia) is Wayland-native.
- Polkit/system-bus-dependent features aren't wired up (no system bus in the
  container), matching the cosmic setup. Noctalia's shell, bar, and panels work
  regardless.
- If you get a black screen, the most likely cause is the DRI/GPU stack — the
  base `cdev` image is expected to provide it (same as cosmic).

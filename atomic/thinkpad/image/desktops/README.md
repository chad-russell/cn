# desktop-blueprint prototypes

Current direction: use **GDM** as the session picker, but keep the actual
launcher and rootfs entirely outside the immutable image so iteration does not
need a `bootc` rebuild.

Status: the prototype now targets these flows:

- sandboxed `niri` session from an OCI-derived rootfs
- GDM entry installed under `/usr/local/share/wayland-sessions/`
- stable launcher path `/usr/local/bin/niri-bwrap-session`
- `Mod+T` -> host `ptyxis`
- `Mod+B` -> Zen Flatpak
- `Mod+E` -> GNOME Text Editor Flatpak

## App-launch bridge: `systemd-run --user`

App launching is handled by the **host user manager**, reached from inside the
sandbox via `systemd-run --user`. The in-sandbox session wrapper imports the
compositor-discovery env (`WAYLAND_DISPLAY`, desktop session vars) into the host
user manager once niri starts, so host commands launched later target this
compositor correctly.

This keeps the bridge simple:

- **no host-side custom broker daemon**
- **no `flatpak-spawn` dependency inside the rootfs**
- **no file-based session handoff** — the host user manager already has the right
  session env imported
- one generic helper instead of one script per named action

## Files

- `manifest.json`
  - example desktoppak v1 payload manifest, copied into the image at
    `/usr/share/desktoppak/manifest.json`
- `desktoppak-manifest-v1.schema.json`
  - draft schema for the eventual generic launcher/tooling
- `desktoppak-manifest-v1.md`
  - notes on the schema and what this prototype currently consumes
- `launch-bwrap-session.sh`
  - preferred prototype
  - extracts the OCI image to a local rootfs once, then runs that rootfs under `bwrap`
  - GDM-safe: no `sudo`, no `seatd`, no VT-only assumptions
  - reads `/usr/share/desktoppak/manifest.json` from the extracted rootfs
  - keeps persistent writable state under the user state root
  - binds the session bus + runtime dir and launches the session
- `Containerfile`
  - rootless, session-payload image definition for the sandboxed compositor
  - intentionally separate from the host bootc image
- `build-rootfs-image.sh`
  - builds the session payload image into your **rootless** podman storage as
    `localhost/niri-session:dev`
- `prepare-rootfs.sh`
  - materializes `localhost/niri-session:dev` into `image/state/rootfs/`
- `bwrap-session.sh`
  - in-sandbox session wrapper; launches and supervises niri
  - (no longer publishes a session-env file — see bridge notes above)
- `session-spawn.sh`
  - the generic app-launch bridge, mounted into the sandbox at
    `/run/desktop-blueprint/bin/session-spawn`
  - calls `systemd-run --user`, forwarding the session env so the host-launched
    app targets this compositor
  - modes: `terminal`, `browser`, `editor`, `flatpak <app-id>`, `host <cmd> [...]`
- `flatpak-spawn-spike.sh`
  - historical note: the earlier `flatpak-spawn --host` spike helper has been
    removed; the bridge now uses `systemd-run --user`
- `niri-config.kdl`
  - copy of `niri/config.kdl`; `Mod+T/B/E` launch through `session-spawn`
- `launch-podman-session.sh`
  - earlier podman-runtime prototype, kept only as a historical reference

## Goal of these prototypes

Prove the core split:

- desktop session payload isolated from the host rootfs
- app launching escapes to the host via `systemd-run --user`
- host Flatpak apps / host binaries appear inside the desktop session

The **preferred** path is the bwrap prototype:

- OCI image for build/distribution
- extracted rootfs for runtime
- bwrap as the session substrate

## Usage

Install the GDM entry and stable launcher path:

```sh
cd image/desktops
./install-gdm-session.sh
```

Build the session payload image in your **rootless** podman storage:

```sh
./build-rootfs-image.sh
```

Then prepare or refresh the extracted rootfs without rebuilding the host:

```sh
./prepare-rootfs.sh --refresh
```

Then log out and pick **Niri (bubblewrap)** from GDM.

Default launch targets:

```text
terminal: /usr/bin/ptyxis
browser:  app.zen_browser.zen
editor:   org.gnome.TextEditor
```

Override them if needed:

```sh
DESKTOP_TERMINAL_CMD=/usr/bin/ptyxis \
DESKTOP_BROWSER_FLATPAK_APP=app.zen_browser.zen \
DESKTOP_EDITOR_FLATPAK_APP=org.gnome.TextEditor \
  /usr/local/bin/niri-bwrap-session
```

Logs go to:

```text
image/state/niri-session/logs/session.log        (niri + session wrapper)
image/state/niri-session/logs/session-spawn.log  (app launches via flatpak-spawn)
image/state/niri-session/logs/flatpak-spawn.log  (Mod+P debug spike)
```

## Expected behavior

- niri + Noctalia start in the isolated session rootfs
- `Mod+T` launches host `ptyxis`
- `Mod+B` launches the Zen Flatpak
- `Mod+E` launches the GNOME Text Editor Flatpak

Each launches on the host but connects back to this niri's Wayland socket, so it
targets this session rather than any other concurrently running desktop session.

## Notes

- The bwrap prototype is the runtime; Podman is only used to build and extract
  the OCI-built rootfs, not as the long-term session runtime.
- The session payload image is deliberately **separate** from the host bootc
  image. `localhost/...` tags are per-storage: a `sudo podman build` image is
  invisible to rootless podman. That is why this directory now has its own
  `build-rootfs-image.sh`.
- `/usr/local/share/wayland-sessions` and `/usr/local/bin` are writable on
  Silverblue, so they are the key to installing/uninstalling the session entry
  without touching the booted image.
- The app-launch contract is now `systemd-run --user` with the session env
  forwarded — no file-based session registry is involved.
- `launch-bwrap-session.sh` copies `niri-config.kdl` into
  `image/state/niri-session/xdg-config/niri/config.kdl` on first run; set
  `NIRI_BWRAP_SYNC_CONFIG=1` to force-sync it again from the repo copy.

## Likely next steps

- factor the launcher behavior into a smaller, explicit contract (manifest-driven)
- decide what state under `desktop-blueprint/state/` is persistent vs ephemeral
- formalize the `session-spawn` action surface into the manifest schema
- optionally reintroduce a narrow allowlist if a tighter security posture is wanted

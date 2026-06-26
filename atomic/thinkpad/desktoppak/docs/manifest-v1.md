# desktoppak manifest v1

Location inside the session payload image:

```text
/usr/share/desktoppak/manifest.json
```

## Required fields

- `name`: simple package/session name, e.g. `niri`
- `display_name`: DM-visible display name
- `session_type`: currently only `wayland`
- `exec`: absolute path to the compositor/session binary inside the rootfs

## Optional fields

### `config.seed`
List of default config files that should be copied from the image into the
user-owned host config area on first install/first launch.

Example:

```json
{
  "config": {
    "seed": [
      {
        "source": "/usr/share/desktoppak/defaults/niri/config.kdl",
        "target": "/home/session/.config/niri/config.kdl"
      }
    ]
  }
}
```

For the current prototype, only the first seed entry is consumed.

### `env`
Environment variables that should be set inside the sandbox before launching the
session binary.

### `host_paths`
Declarative list of extra host paths that should be exposed inside the main
session sandbox, for example wallpapers or host app discovery roots.

Each entry has:
- `type`: `ro` or `rw`
- `host`: host-side source path
- `guest`: in-sandbox destination path
- `optional`: if true, missing host path is ignored

### `binds`
Declarative list of core host->guest bind mounts. The current prototype still
hardcodes the base runtime bind set (`/run/dbus`, `/run/udev`, `/run/systemd`,
`$XDG_RUNTIME_DIR`) and consumes `host_paths` separately.

## Current prototype support

The current Niri prototype consumes this subset from the manifest:

- `name`
- `display_name`
- `exec`
- all `config.seed[*]` entries targeting `/home/session/.config/...`
- `env.XDG_SESSION_DESKTOP`
- `env.XDG_CURRENT_DESKTOP`
- `env.XDG_SESSION_TYPE`
- `env.LIBSEAT_BACKEND`
- `env.XDG_DATA_DIRS`
- `env.QT_QPA_PLATFORM`
- `env.QT_WAYLAND_DISABLE_WINDOWDECORATIONS`
- `host_paths[*]`

Everything else is forward-looking schema for the eventual generic
`desktoppak` launcher.

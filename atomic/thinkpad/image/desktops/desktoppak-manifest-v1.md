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

### `binds`
Declarative list of host->guest bind mounts. The current prototype documents
these here but still hardcodes the actual bind set in the launcher. A future
`desktoppak launch` should consume this field directly.

## Current prototype support

The current Niri prototype consumes this subset from the manifest:

- `name`
- `display_name`
- `exec`
- `config.seed[0].source`
- `env.XDG_SESSION_DESKTOP`
- `env.XDG_CURRENT_DESKTOP`
- `env.XDG_SESSION_TYPE`
- `env.LIBSEAT_BACKEND`

Everything else is forward-looking schema for the eventual generic
`desktoppak` launcher.

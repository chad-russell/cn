# desktoppak

Prototype for per-user desktop/compositor payloads.

A desktoppak package is:

- an OCI-built session payload image
- extracted into per-user storage
- launched under `bwrap`
- registered with the display manager as needed

## Layout

```text
desktoppak/
├── cli/                 # desktoppak command implementation
├── runtime/             # generic session runtime helpers
├── docs/                # manifest docs/schema
├── payloads/            # concrete desktop payloads
│   ├── niri/
│   └── cosmic/
└── README.md
```

## CLI

Current entrypoint:

```bash
python3 desktoppak/cli/desktoppak.py ...
```

Commands:

```bash
desktoppak install <name> <oci-ref>
desktoppak update <name>
desktoppak uninstall <name>
desktoppak list
desktoppak register <name> --dm gdm
desktoppak unregister <name> --dm gdm
desktoppak launch <name>
```

## Storage

```text
~/.local/share/desktoppak/<name>/
├── install/
│   ├── rootfs/
│   ├── image-ref
│   ├── image-id
│   └── manifest.json
├── config/
└── state/
```

## Runtime model

- payload rootfs is built with rootless `podman`
- rootfs is extracted per-user
- runtime launcher is `runtime/launch-bwrap-session.sh`
- in-sandbox helpers are:
  - `runtime/desktoppak-session.sh`
  - `runtime/desktoppak-spawn.sh`
- host app launching uses `flatpak-spawn --host`
- GDM registration writes into `/usr/local/share/wayland-sessions`

## Notes

- `install` is transactional.
- extraction uses `tar --no-same-owner --no-same-permissions` so files stay
  user-owned.
- `update` uses per-run staging/backup dirs to avoid collisions with stale
  failed-run leftovers.
- current config seeding support targets `/home/session/.config/...`.

## Current payloads

- `payloads/niri/`
- `payloads/cosmic/`

# desktoppak (Python v1 prototype)

Initial Python CLI for per-user desktop session payloads.

## Commands

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

## Notes

- `install` / `update` use rootless `podman`.
- Rootfs extraction uses `tar --no-same-owner`, so files in the extracted tree
  stay user-owned instead of preserving container root ownership.
- `register` / `unregister` write GDM session entries under
  `/usr/local/share/wayland-sessions`, so they use `sudo`.
- `launch` currently reuses `image/desktops/launch-bwrap-session.sh` as the
  execution engine, with per-package rootfs/config/state roots injected via env.
- v1 currently supports payloads whose manifest seeds config into
  `/home/session/.config/...`.
- `install` is transactional: if the rootfs is missing a manifest, the temporary
  install is cleaned up instead of leaving a half-installed package behind.

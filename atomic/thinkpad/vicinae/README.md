# vicinae/ — archived container prototype

**Current production setup is no longer the container in this directory.**

Vicinae now runs the same way as Noctalia on the ThinkPad image:

- install the **host `vicinae` package** in `image/Containerfile`
- start it through **`image/vicinae-bwrap`**
- keep config/state/cache/data isolated under
  `~/.local/share/bwrap/vicinae/`
- use the native host `vicinae toggle` / `vicinae open` / etc. commands for
  low-latency IPC to the running server

That architecture won over the old Podman version because the real goal here is
**state containment**, not container namespaces: bwrap keeps Vicinae from
polluting the host XDG tree, while preserving a native-fast keybind path.

## What remains in this directory

The files here are kept as **historical reference** for the older containerized
approach:

- `Containerfile`
- `run.sh`
- `toggle.sh`
- `diagnose.sh`
- `vicinae-host-launch`

They are **not** the current startup path for the ThinkPad image or the active
niri configuration.

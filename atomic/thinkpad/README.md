# ThinkPad — atomic workstation repo

This repo holds machine-specific infrastructure for a Fedora-based atomic (bootc)
host.

## Main projects here

```text
.
├── host-image/     # minimal bootc host image
├── desktoppak/     # desktop/compositor packaging + runtime prototype
├── nebula/         # Nebula VPN container/service
├── wycliffe-vpn/   # on-demand GlobalProtect wrapper
├── shellboxes/     # vendored shellbox box definitions (replaces cdev)
└── systemd/        # user/systemd units (mostly user services for now)
```

## Guiding principle

Keep the host small and explicit.

- host OS changes belong in `host-image/`
- desktop sessions belong in `desktoppak/`
- apps and dev tools should prefer shellboxes, Flatpaks, or other isolated
  models over being layered onto the host
- persistent mutable state should live in obvious, named locations

## Current architecture

### `host-image/`
A minimal bootc-managed host image. It is intentionally small: host-level
choices that truly belong in the base OS (convenience packages, disabling
SELinux, removing `toolbox`, adding `distrobox`). It also bakes the
`shellbox-mount@.service` template so shellboxes can be auto-mounted at boot.
See `host-image/README.md`.

### `desktoppak/`
A separate project for self-contained desktop/compositor session payloads (CLI,
generic bwrap runtime, manifest docs/schema, Niri payload). Desktop
experimentation happens here, not by installing compositors on the host. See
`desktoppak/README.md`.

### `nebula/`
Rootful Podman/Quadlet-based Nebula VPN setup.

### `wycliffe-vpn/`
On-demand Wycliffe GlobalProtect container workflow. See
`wycliffe-vpn/README.md`.

### `shellboxes/`
Vendored definitions for **shellbox** dev environments. **This replaces the
old `cdev/` bespoke dev container.**

`shellbox` itself lives in a separate repo (`~/Code/cn/shellbox/`). It is a
lightweight devshell/container utility: each **box** is a named OCI-image-backed
environment whose manifest (`shellbox.toml`) is the single source of truth.
Boxes are symlinked (via `shellbox link`) into shellbox's boxes dir from here so
they stay version-controlled.

Current boxes:

- `default/` — generic CLI tools (`htop`, `rg`, `fd`)
- `nvim/` — self-contained neovim (XDG dirs redirected into the box)
- `opencode/` — self-contained `sst/opencode` coding agent
- `pi/` — self-contained `pi` coding agent TUI

Each self-contained box keeps all of its config/data/state/cache inside the box
directory (via absolute-literal XDG env redirection in `shellbox.toml`), so it
never touches `~/.config`, `~/.local/share`, etc.

Typical workflow:

```bash
shellbox link ~/Code/cn/atomic/thinkpad/shellboxes/nvim
shellbox build nvim
sudo shellbox mount nvim
shellbox export nvim nvim     # add ~/.local/share/shellbox/exports/bin to PATH once
nvim ~/any/file
```

See the `shellbox` README (`~/Code/cn/shellbox/README.md`) for the full tool.

### `systemd/`
Systemd units, mostly **user** services for now (`systemd/user/`), with room to
add system units later. The current unit, `opencode-web.service`, runs the
opencode web frontend as a user service by calling into the `opencode` shellbox
via `shellbox run`. The composefs mount it depends on is brought up at boot by
the `shellbox-mount@opencode.service` template baked into the host image. To
install a unit:

```bash
mkdir -p ~/.config/systemd/user
ln -s ~/Code/cn/atomic/thinkpad/systemd/user/<unit> ~/.config/systemd/user/
systemctl --user daemon-reload
loginctl enable-linger crussell      # one-time: run before login
systemctl --user enable --now <unit>
```

## State philosophy

Prefer explicit state roots over accidental host drift.

Examples:

- `~/Code` for deliberate work
- `~/.var/app/` for Flatpak state
- shellbox storage: `~/.local/share/shellbox/` (boxes, store, exports) and
  `~/.local/state/shellbox/` (per-box derived state)
- `~/.local/share/desktoppak/` for desktoppak installs/config/state

## Notes

- `host-image/` and `desktoppak/` are intentionally separate concerns.
- There is no native host fallback desktop session in the host image.
- Desktop experimentation should happen through desktoppak payloads rather than
  by installing compositors/companions directly on the host.
- Dev tools live in shellboxes, not on the host image. The old `cdev/` bespoke
  container is gone.

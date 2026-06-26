# host-image/

Minimal bootc-based Fedora host image for this machine.

## Purpose

This project is now intentionally small. Desktop/compositor payloads no longer
live here; they live in `../desktoppak/`.

`host-image/` is for host-level choices that should truly be part of the base
OS image.

## What it changes

Currently:

- removes `toolbox`
- installs `distrobox`
- installs small host convenience packages:
  - `fastfetch`
  - `neovim`
- disables SELinux for this personal-laptop setup
- bakes a templated `shellbox-mount@.service` unit so shellboxes can be auto-mounted at boot

## What does NOT live here anymore

Not in the host image:

- `niri`
- `noctalia`
- `vicinae`
- custom desktop sessions
- desktoppak runtime scripts
- desktoppak payload images

Those now live under `../desktoppak/`.

## Files

```text
host-image/
├── Containerfile
├── build.sh
├── switch.sh
├── upgrade.sh
├── systemd/
│   └── shellbox-mount@.service   # templated boot-mount unit
└── README.md
```

## Lifecycle

```bash
cd host-image/

# first adoption onto a stock Fedora host
./build.sh
./switch.sh
systemctl reboot

# routine rebuilds afterward
./build.sh
./upgrade.sh
systemctl reboot
```

## Image reference

Builds use:

```text
localhost/host-image-thinkpad:<fedora-version>
```

and stamp the booted system with:

```text
/usr/lib/host-image-thinkpad-version
```

## Notes

- Built locally with `sudo podman build` so `bootc` can read the image from
  root containers storage.
- `bootc switch` is for first adoption or changing image references.
- `bootc upgrade` is the routine command after rebuilding the same tagged image.
- The image stays intentionally minimal; desktop experimentation belongs in
  desktoppak, not here.

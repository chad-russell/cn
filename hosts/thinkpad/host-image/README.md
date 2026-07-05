# host-image/

Minimal bootc-based Fedora host image for this machine.

## Purpose

`host-image/` is for host-level choices that should truly be part of the base
OS image — including the compositors (`niri` and COSMIC), which ship directly
here rather than in a separate payload layer.

## What it changes

Currently:

- removes `toolbox`
- installs `distrobox`
- installs compositors from COPR:
  - `niri` + `xwayland-satellite` (from `yalter/niri`)
  - `cosmic-desktop` (from `ryanabx/cosmic-epoch`)
- installs small host convenience packages:
  - `fastfetch`
  - `neovim`
  - `oh-my-posh` (prompt renderer; hooks the interactive shell in `~/.zshrc` — belongs on the host, not in a shellbox, because it runs on every prompt render and can't pay a per-invocation bwrap spawn)
- disables SELinux for this personal-laptop setup


## Files

```text
host-image/
├── Containerfile
├── build.sh
├── switch.sh
├── upgrade.sh
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

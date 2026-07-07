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
  - `just` + `fzf` — back the `cjust` task menu (see `hosts/thinkpad/Justfile`);
    host-native because `cjust` must work before any sandbox is set up
  - `nodejs` + `npm` — used by `cjust opencode-install` to install the
    `opencode-ai` package globally (prefix `~/.local`). opencode stays on the
    host because it's the AI coding agent and needs full host control when
    something breaks, not subject to sandbox rules
  - `oh-my-posh` — prompt renderer; hooks the interactive shell in `~/.zshrc`.
    Host-native because it runs on every prompt render and can't pay a
    per-invocation sandbox spawn
- disables SELinux for this personal-laptop setup
- bakes a bootc static karg (`usbcore.autosuspend=-1`) into the image via
  `/usr/lib/bootc/kargs.d/10-usb-autosuspend.toml`. This is the real fix for
  the Dell P3225QE external monitor flapping DP-1 every ~3s over USB-C on this
  Lunar Lake (xe) host — the USB-C/DP tunnel was cycling in/out of runtime
  suspend. Applied to every deployment staged from this image (`bootc install`
  and `bootc upgrade`); removing the file retracts the karg on the next upgrade.


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

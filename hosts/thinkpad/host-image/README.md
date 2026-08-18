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
├── build.sh     # break-glass LOCAL build (normal flow builds on bees)
├── switch.sh    # one-time adopt of the bees registry reference
├── upgrade.sh   # routine pull-from-registry + stage (bootc upgrade)
└── README.md
```

## Lifecycle — NORMAL (registry-driven, built on bees)

bees builds + publishes this image daily (`thinkpad-image-build.timer`, see
`hosts/bees/thinkpad-registry.nix`) to its zot registry at
`10.10.0.6:5000/cn/thinkpad-host:44` (Nebula-only, plain HTTP inside the
tunnel). Zot retention keeps the rolling `:44` plus the last 3 immutable
`44-<sha>-<ts>` tags and GCs the rest.

```bash
# one-time: adopt the registry image (from a stock or local-flow host)
cjust image-switch
systemctl reboot

# routine — "get me the latest bees built" (diff-only pull, then reboot)
cjust image-upgrade
systemctl reboot

# "I pushed to origin/main and want it NOW" — remote build, wait, pull, stage
cjust image-rebuild
systemctl reboot
```

## Lifecycle — break-glass (local, while bees/Nebula is down)

```bash
cd host-image/
./build.sh
./switch.sh        # if on stock Fedora; else skip to upgrade
systemctl reboot
```

The registry reference and the local `containers-storage:` reference are
different bootc references — moving between them is always a `switch.sh`
(`bootc switch`), not an `upgrade`.

## Image reference

Registry builds (normal flow):

```text
10.10.0.6:5000/cn/thinkpad-host:44
```

Local builds (break-glass) use:

```text
localhost/host-image-thinkpad:<fedora-version>
```

Both stamp the booted system with:

```text
/usr/lib/host-image-thinkpad-version
```

## Notes

- Registry transport security is Nebula itself (WireGuard); zot is bound to
  bees's overlay IP only, and bees runs no host firewall on the LAN side of
  that address. The image and the host each carry an
  `/etc/containers/registries.conf.d` insecure-registry drop-in
  (`[[registry]] insecure = true`) so podman/skopeo/bootc can talk to it —
  switch.sh bootstraps the host copy on first run (bootc has no `--insecure`
  flag; it reads the same drop-ins).
- `bootc switch` is for first adoption or changing image references.
- `bootc upgrade` is the routine command after rebuilding the same reference.
- Rebuilds are detected by a unique OCI label per build (see build.sh), so
  `upgrade` never no-ops on a rebuilt `:44`.

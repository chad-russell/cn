# ThinkPad — Fedora Silverblue (atomic) configuration

This directory holds various configurations related the ThinkPad machine,
which uses bootc with **Fedora Silverblue 44**.

The guiding principle: **the host should be immutable, and mutable state should
exist only in explicit, named pockets.** The base image is built from this repo;
apps and tools run in Flatpaks, Podman containers, or bubblewrap wrappers where
possible; and anything that genuinely needs host session/hardware integration is
kept as a narrow, documented exception.

Ultimately, we are moving toward a world where the entire disk (not only the sys root but all of $HOME, etc) is
rolled back to a known state on every boot (impermanence). The only things that will be persistent at that point are
container volumes that are explicitly named and tracked carefully. This is in the distant future but that is part of the goal.

## The tier model

Every component belongs to exactly one tier. Rule of thumb: push everything
as far down the list as possible.

| Tier                         | What lives here                                                                         | Examples                                          | Backup strategy                                                                 |
| ---------------------------- | --------------------------------------------------------------------------------------- | ------------------------------------------------- | ------------------------------------------------------------------------------- |
| **0. Base image**            | Custom Silverblue image (`image/`): host packages that genuinely belong on the host.    | niri, Noctalia binary, distrobox                  | Repo is the source of truth; rebuild + `bootc upgrade`. Rollback is one reboot. |
| **1. Host-session wrappers** | Host binaries that need native session/hardware access but get isolated writable state. | `noctalia-bwrap`                                  | Wrapper in repo; mutable state under `~/.local/share/bwrap/<app>/`.             |
| **2. Flatpaks**              | GUI apps whose sandbox/state model is good enough.                                      | Zen, Proton VPN, Proton Pass, Bazaar              | Flatpak export/list plus selected `~/.var/app/*` state if needed.               |
| **3. Containers**            | CLI tools, dev toolchains, services, VPNs.                                              | Nebula VPN, dev toolbox (`./cdev`), GlobalProtect | Images are rebuildable; only selected **named volumes** need backing up.        |
| **4. Deliberate host files** | Real host files that are intentionally not sandboxed.                                   | `~/Code`, SSH config/keys                         | The git repo and explicitly-managed files are the backup.                       |

### Host cleanliness and mutable state

The desired end state is: **backup = this repo + selected named mutable-state
roots.** The real host `$HOME` should contain deliberate work and a small number
of obvious state roots, not years of accidental dotfile/config/cache drift from
programs that were tried once and forgotten.

Current state roots:

| Root                                         | Owner / purpose                              | Backup stance                                                                        |
| -------------------------------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------ |
| `~/Code`                                     | Deliberate working tree / projects           | Backed by git/remotes as appropriate.                                                |
| `~/.local/share/containers/storage/volumes/` | Podman-managed named volumes                 | Back up only selected stateful volumes; don't bind these directly outside Podman.    |
| `~/.local/share/bwrap/<app>/`                | Bubblewrap-managed plain-directory “volumes” | Back up selected state roots (`xdg-config`, `xdg-state`, `xdg-data`); ignore caches. |
| `~/.var/app/`                                | Flatpak app state                            | Back up only apps whose state matters.                                               |

For Noctalia specifically, `noctalia-bwrap` exposes the host root read-only,
uses an ephemeral tmpfs `$HOME`, then mounts only the conventional XDG roots as
persistent writable volumes: `~/.config`, `~/.local/state`, `~/.local/share`, and
`~/.cache` are backed by
`~/.local/share/bwrap/noctalia/{xdg-config,xdg-state,xdg-data,xdg-cache}`.
`~/Pictures/Wallpapers` is an explicit readonly host input so Noctalia can read
wallpapers without opening the rest of `$HOME`.

Rules of thumb:

1. **Do not vendor mutable application state into git.** Keep app state volumes
   as plain directories that can be audited, snapshotted, exported, or deleted
   independently. Git tracks the machinery, not the runtime state.
2. **Use Podman volumes for real containers.** Podman owns its storage metadata;
   treat `~/.local/share/containers/...` as implementation-owned and manage it
   with Podman export/import or direct backup of selected named volumes.
3. **Use bwrap volumes for host-session apps.** Apps like Noctalia need native
   Wayland/niri/logind/`/sys` integration, so they run as host binaries through
   bubblewrap. The host root is visible read-only, `$HOME` is ephemeral, and
   only explicitly-mounted XDG roots are persistent plain-directory volumes under
   `~/.local/share/bwrap/<app>/`.
4. **Caches are disposable.** Prefer layouts where cache directories are named
   and can be excluded from backups or deleted wholesale.
5. **Anything that writes outside its assigned pocket is a bug to fix.** The long
   term direction is an immutable system with opt-in mutability, potentially
   reinforced later with btrfs snapshot/reset strategies.

## Decisions (so we don't re-litigate them)

1. **Compositor: Niri, with host-session shell integration.** Niri is installed
   in the custom bootc image. Noctalia is also installed on the host image, but
   is launched through `noctalia-bwrap`: host session integration stays native
   (Wayland, niri IPC, logind, `/sys` brightness notifications, PipeWire,
   D-Bus), while writable XDG state is redirected to
   `~/.local/share/bwrap/noctalia/`.
2. **Nebula runs as a rootful podman container.** It needs `CAP_NET_ADMIN`
   and a host TUN to route host traffic, so rootful + `--network=host` is
   the boring, reliable choice. Start/stop via systemd = VPN on/off.
   - **Image pinned to nebula 1.10.3** — the homelab CA issues `NEBULA
CERTIFICATE V2` certs, which require nebula >= 1.10.0. Pinning below
     1.10.x fails with `unsupported certificate format: NEBULA CERTIFICATE
V2`. (Confirmed: bees runs 1.10.3.)
   - **Auto-starts at boot.** systemd marks Quadlet-generated units as
     `generated` state, and on Fedora 44 `systemctl enable` refuses them,
     so `install.sh` falls back to a wants symlink into the generator
     output (`/etc/systemd/system/multi-user.target.wants/nebula.service`
     -> `/run/systemd/generator/nebula.service`). The Quadlet generator runs
     early at boot, before `multi-user.target` evaluates its wants.
   - **Manual toggle:** `sudo systemctl stop nebula` stays off until
     `start` or a reboot; `sudo systemctl start nebula` brings it back.
   - **Verified working:** thinkpad = `10.10.0.10`, bees/bee reachable
     over the overlay at single-digit-ms RTT.
3. **Dotfiles & cruft: separate `$HOME` for the dev container.** The
   principle: **host filesystem holds your deliberate work; volumes hold
   isolated tool state. Nothing else touches the host.** The dev container is
   a plain `podman create` (NOT a toolbx — toolbx forces a shared host
   `$HOME`, which leaks nvim plugins/caches/history onto the host). Instead
   it has a **separate `$HOME`** as a named volume (`cdev-home`), so the
   container physically cannot write to your host home. `~/Code` stays on the
   host (git-tracked work, visible from every context) and is bind-mounted in.
   `~/.ssh`, `~/.gitconfig`, and the `/run/user/$UID` tmpfs (ssh-agent,
   Wayland) are bind-mounted too. **Nothing survives a recreate** —
   `create.sh` wipes `dev-home` each run, so every recreate is a cold test of
   whether the image alone reproduces the environment; anything you miss
   becomes a `Containerfile` line next time. Tool config (zsh, oh-my-posh,
   nvim) is baked into the image at `/usr/share/dev-shell/` (ZDOTDIR for zsh,
   XDG_CONFIG_HOME via the nvim wrapper), never written to `$HOME`. Host
   `$HOME` receives only what GNOME/flatpaks genuinely need. See
   `cdev/README.md`.
4. **Neovim: full config ported to lazy.nvim, baked into the dev container.**
   The old ~600-line nixvim config (LSP servers, treesitter 0.12 workarounds,
   telescope/flash/trouble/etc.) is ported to `atomic/thinkpad/cdev/shell/nvim/`
   as a lazy.nvim config. A `/usr/local/bin/nvim` wrapper redirects
   `XDG_CONFIG_HOME` so nvim reads the baked config by default, or the live
   repo dir when `NVIM_DEV_CONFIG_HOME` is set — enabling fast iteration
   (edit `.lua`, relaunch) without rebuilding. `nvim-check.sh` headless-boots
   - Lazy-syncs as the validation gate. See `cdev/README.md`.
5. **Wycliffe GlobalProtect VPN runs in a rootful podman container** using
   the official `gpclient` image (`yuezk/globalprotect-openconnect`). The
   GNOME AnyConnect option is unusable here — Wycliffe requires CAS/SAML
   and rejects clients below v6.0, which stock `openconnect` doesn't
   implement. It's an **on-demand script**, not a boot service, because
   every connection needs interactive browser SSO (`gpclient ... --browser
remote`). Run `./connect.sh`, open the printed URL in Zen, complete
   login, `Ctrl+C` to hang up.
6. **Custom base image, bluefin-style and local-only, bootc-native.** The
   base is a thin custom image defined in `image/` (a `Containerfile` over the
   official Silverblue ostree base, same one ublue/bluefin/finpilot derive
   from). Host packages are still deliberate exceptions, not a dumping ground:
   today they include distrobox, niri, Noctalia, and small host-session helpers
   such as `brightnessctl`. It uses the modern **bootc** build model (the
   future-facing front-end; it still uses ostree/libostree under the hood):
   `dnf5` for build-time package changes and `bootc container lint` to finalize.
   Built and switched **entirely locally** (no registry, no GitHub Actions):
   `sudo podman build` then `bootc switch --transport containers-storage
localhost/...`; routine changes are `bootc upgrade`. The bespoke dev
   container in `cdev/` is unaffected — still a plain `podman create` with a
   separate `$HOME`; distrobox here just provides the `distrobox` CLI on the
   host for ad-hoc containers. Safety net is `bootc rollback`; backup is the
   repo plus selected named state roots. See `image/README.md`.

## Deferred / pending evaluation

These were part of the old NixOS config and are **not** applied yet. Revisit
if symptoms appear:

- **iwlwifi TSO/GSO workaround** — Lunar Lake WiFi firmware crashes
  (multi-second freezes) without `options iwlwifi power_save=0` + a
  NetworkManager dispatcher script running `ethtool -K wlp0s20f3 tso off gso off`.
  See the old `thinkpad/NOTES.md`. Highest-priority item if the machine
  starts freezing.
- **`vm.swappiness=10`** — prevents long-running apps drifting to swap.
- **Battery charge thresholds (75–80%)** — udev rule on `BAT0`.
- **Split DNS for `dev.crussell.io`** via AdGuardHome on bee over Nebula.

## Current layout

```
atomic/thinkpad/
├── README.md              # this file
├── image/                   # build #0 — custom Silverblue base image (local, no registry)
│   ├── Containerfile        # FROM silverblue:44; distrobox + niri + Noctalia + bootc lint
│   ├── noctalia-bwrap       # host-session Noctalia wrapper with named bwrap state volumes
│   ├── build.sh             # sudo podman build (root, so bootc can read it)
│   ├── switch.sh            # bootc switch --transport containers-storage
│   ├── upgrade.sh           # routine bootc upgrade after rebuild
│   ├── setup.sh             # one-shot build + switch
│   └── README.md
├── nebula/                # build #1 — rootful VPN container (overlay)
│   ├── image/
│   │   ├── Containerfile
│   │   └── build.sh
│   ├── config.yaml           # adapted from nebula/configs/thinkpad.yaml
│   ├── nebula.container      # Quadlet unit (system service, boot-autostart)
│   ├── seed.sh               # populate the nebula-config volume (decrypts key)
│   ├── install.sh            # install the Quadlet + enable+start
│   └── setup.sh              # one-shot: build → seed → install
├── wycliffe-vpn/           # build #2 — Wycliffe GlobalProtect VPN (on-demand)
│   ├── connect.sh            # sudo podman run ... gpclient connect --browser remote
│   └── README.md
└── cdev/                   # build #3 — the dev container - plan rootless podman container
    ├── Containerfile         # fedora-toolbox:44 + tools + LSPs/formatters + wrapper
    ├── build.sh              # podman build -t localhost/cdev
    ├── shell/                # dotfiles (source of truth = this repo)
    │   ├── .zshenv
    │   ├── .zshrc
    │   ├── oh-my-posh.json
    │   └── nvim/             # lazy.nvim config (full nixvim port)
    │       ├── init.lua
    │       ├── lua/config/   # options, keymaps, autocmds, lsp, treesitter fix
    │       ├── lua/plugins/  # one lazy spec file per plugin
    │       └── queries/markdown/highlights.scm
    └── README.md
```

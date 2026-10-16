# ThinkPad — atomic workstation repo

This repo holds machine-specific infrastructure for a Fedora-based atomic (bootc)
host.

## Main projects here

```text
.
├── host-image/     # minimal bootc host image
├── nebula/         # Nebula VPN container/service
├── backup/         # restic S3 backup (units in host-image/; image build + seeding here)
├── wycliffe-vpn/   # on-demand GlobalProtect wrapper
├── hyprland/       # round-2 Hyprland exploration kit (layered, not baked)
└── bubblebox/      # declarative host profile (packages + dotfiles + units)
    ├── profile.toml   # desired package set + [[files]] + [[units]] declarations
    ├── files/         # host-native dotfiles, mirroring $HOME (managed by `bubblebox apply`)
    └── units/         # systemd user units (managed by `bubblebox apply`)
```

## Guiding principle

Keep the host small and explicit.

- host OS changes belong in `host-image/`
- apps and dev tools should prefer bubblebox sandboxes, Flatpaks, or other
  isolated models over being layered onto the host
- persistent mutable state should live in obvious, named locations
- the rare dotfile that must live host-native (e.g. oh-my-posh, which runs on
  every prompt render and so can't pay a per-invocation sandbox spawn) is
  tracked under `bubblebox/files/` and symlinked into `$HOME` by `bubblebox
  apply` (declared via `[[files]]` in `bubblebox/profile.toml`)

## Task runner: `cjust`

`cjust` is the single entry point for setting up and maintaining this machine.
It's a thin wrapper (defined in `bubblebox/files/.zshrc`) around the task runner
`just`, pointing at `hosts/thinkpad/Justfile`. `just` and `fzf` are baked into
the host image so it works before any sandbox is set up.

```bash
cjust                  # fuzzy recipe chooser (just --choose)
cjust setup              # first run: install pinned engine + doctor + apply
cjust bubblebox-apply    # apply the committed profile + lock (tools, dotfiles, units)
cjust bubblebox-upgrade  # pull whatever CI last published, apply, update the lock
cjust bubblebox-plan     # dry-run (add --refresh to preview an upgrade)
cjust status           # show host-image / bootc / bubblebox state
cjust -l               # list all recipes
```

Dotfiles and systemd user units are declared in `bubblebox/profile.toml` (the
`[[files]]` and `[[units]]` sections) and realized by `cjust bubblebox-apply`.
The profile is applied **in place**: `~/.config/bubblebox/profile.toml` is a
symlink to `bubblebox/profile.toml` here, and the engine mirrors the realized
lock to `bubblebox/profile.lock` — commit it alongside profile edits (the
`flake.lock` analog).

`thinkpad-bubblebox-check.timer` runs daily: a read-only `bubblebox plan`
for **drift** (live state ≠ committed profile/lock) and `plan --refresh` for
**updates** (CI published newer builds). One ntfy ping (homelab-alerts) per
distinct state, silent when healthy or away from home; it never applies.

**GNOME settings (dconf)** are declared in
`bubblebox/files/.config/dconf/bubblebox.d/00-thinkpad` (a plain dconf
keyfile of curated preferences). It is compiled into a database layered
*under* your personal one via `DCONF_PROFILE` (environment.d), so declared
values are **defaults**: changing something in Settings still works and wins,
`dconf reset <key>` falls back to the repo value, and removing a key from the
keyfile removes the default. `dconf-bubblebox status` shows declared keys
your personal db overrides (the daily check pings when one diverges);
`dconf-bubblebox adopt` clears redundant personal copies so the declared
layer shows through (backup first; run once after the first login with the
profile); `dconf-bubblebox accept <key>` drops one override. To declare a new
setting: change it in Settings, `dconf dump /that/path/`, copy the key into the
keyfile, `cjust bubblebox-apply`.

**The rest of the user layer is declared too**: `.gitconfig`,
`mimeapps.list`, `monitors.xml`, GTK `settings.ini` (non-GNOME sessions),
the caelestia `shell.json`, login autostart (real `.desktop` files), and the
user flatpak overrides — all `[[files]]`, all content-identical to what the
machine had. `~/.config/containers/containers.conf` is NOT declared: its
`compose_providers` path (`~/.local/bin/podman-compose`) doesn't exist — dead
config, safe to delete. The dev-project quadlets under
`~/.config/containers/systemd/` stay symlinked by their per-project
`install.sh` recipes (repo-tracked sources).

**Flatpak apps** are declared in `bubblebox/profile.toml` `[flatpak]` (the
per-user installation). `cjust bubblebox-apply` installs missing apps and
re-installs any you removed by hand; dropping an app from the list
uninstalls it. Apps installed some other way are reported as "unmanaged" by
`cjust bubblebox-plan` and left alone. Updates are still `flatpak update`.
`cjust flatpak-migrate-to-user` is the one-time move off the old system
installation (removes a system copy only once the user copy exists; app data
in `~/.var/app` is shared and untouched).

## Current architecture

### `host-image/`
A minimal bootc-managed host image. It is intentionally small: host-level
choices that truly belong in the base OS (convenience packages, disabling
SELinux, adding `distrobox` — the base image's `toolbox` stays — the niri
compositor stack; `nodejs` stays for the npm-managed dev CLIs —
railway, agent-browser). See
`host-image/README.md`.

The image is built **on bees** (daily `thinkpad-image-build.timer` + on-demand
`cjust image-rebuild`) and published to bees's zot registry
(`10.10.0.6:5000/cn/thinkpad-host:stable`, Nebula-only). `cjust image-upgrade`
pulls only the changed layers and stages the new deployment; it goes live on
the next reboot. The bubblebox timer `thinkpad-image-update.timer` automates
the routine path (daily stage + ntfy lag alert; see
`bubblebox/files/.local/bin/thinkpad-image-update`), and
`thinkpad-image-health.service` gates every boot — it asserts the booted
image's load-bearing artifacts (session, shell, version stamp) and pings
ntfy if one is missing. Recovery stays manual by design:
`bootc rollback` + reboot. Local `./build.sh`
remains as the break-glass path. See `hosts/bees/thinkpad-registry.nix` for
the registry + build service.

### `nebula/`
Rootful Podman/Quadlet-based Nebula VPN setup. The Quadlet ships in the host
image (`host-image/quadlets/`); this dir keeps the container image build and
one-time secret seeding (`setup.sh`).

### Nebula overlay hostnames

Every NixOS host resolves overlay names (`bees`, `bee`, `nas`, …) through
`modules/nebula-hosts.nix` ← `lib/host-meta.nix`. The thinkpad gets the same
entries by baking the rendered fragment into the **host image**
(`host-image/Containerfile` step 3.7 → `/usr/etc/hosts`): ostree 3-way merges
image defaults into the live `/etc/hosts` on every upgrade, so `ping bees`
works and future `host-meta.nix` edits flow in automatically — as long as the
live `/etc/hosts` is never hand-edited (a modified copy stops tracking the
image).

```bash
# after editing lib/host-meta.nix (anywhere the flake runs):
nix run .#render-thinkpad-hosts   # regenerate hosts/thinkpad/host-image/nebula-hosts
# `nix flake check` fails if the committed fragment is stale.

# on the thinkpad, before the next image upgrade + reboot (sudo):
cjust hosts-sync                  # append the same fragment to /etc/hosts now
```

`hosts-sync` is idempotent and appends the exact bytes the image will later
ship, so the eventual ostree merge stays clean.

### `wycliffe-vpn/`
On-demand Wycliffe GlobalProtect container workflow. See
`wycliffe-vpn/README.md`.

### `hyprland/`
Round-2 Hyprland exploration kit (2026-11): runbook + skeleton
`hyprland.lua` (float-by-default, per-workspace scrolling/monocle layouts) +
a quickshell template unit. Exploration deliberately stays OUT of the host
image — Hyprland is layered once via `rpm-ostree` from the `mineiro/hyprland`
COPR (F44 ships no hyprland package) and everything else iterates in
`~/.config`. Only a keeper gets baked into `host-image/`. See
`hyprland/README.md`.

### `bubblebox/`
The host's **bubblebox profile** (`profile.toml`) — the desired set of bubblebox
tools to install, the source registry it resolves them from, **plus** the
host-resident dotfiles (`[[files]]`) and systemd user units (`[[units]]`). This
is the `flake.nix` analog: a declarative input list that `bubblebox apply`
realizes into a pinned generation (`profile.lock`). Alongside the profile live
`files/` (the dotfile sources, mirroring `$HOME`) and `units/` (the systemd unit
sources). It's the host-specific bubblebox config, so it lives here alongside
the rest of the host config.

bubblebox itself spans three repos / concerns:

| concern | location | holds |
|---|---|---|
| **engine** | `~/Code/bubblebox` | the Rust CLI + FUSE server (`bubblebox build/run/apply/...`) |
| **packages** | `~/Code/bubblebox-pkgs` | per-tool `Containerfile` + `entrypoint.toml` (the nixpkgs-analog source) |
| **profile** | this dir (`bubblebox/profile.toml`) | the host's desired package set + source registration + `[[files]]` / `[[units]]` |

A **package** is an OCI image (a `Containerfile`); an **entrypoint** is how
bubblebox runs it (which binary to exec, what to compose in, binds/env) —
authored alongside the Containerfile because the package author knows what the
tool needs. **Config / dotfiles** are a separate concern: every tool reads its
personal config from the host `$HOME` via `writable_home` (e.g. aws reads
`~/.aws/config`, vicinae reads `~/.config/vicinae/`, nvim reads
`~/.config/nvim`), tracked under `bubblebox/files/` and declared in `[[files]]`
(see [Host-resident dotfiles](#host-resident-dotfiles-bubbleboxfiles--files)
below). Runtime state that's regenerable (nvim's plugin tree + undo history,
zoxide's db) is isolated to bubblebox-owned dirs via `/persist` binds.

The laptop is a pure bubblebox **consumer**: the engine is a pinned Forgejo
release (`bubblebox_version` in the Justfile, installed by `cjust
bubblebox-install`), and packages are built, signed, and published to the bees
cache by bubblebox-pkgs CI — nothing builds locally by default.
`cjust bubblebox-apply` pulls the locked packages and generates wrappers at
`~/.local/bin/<tool>`; each tool auto-mounts on first invocation (rootless
FUSE), then `nvim` / `aws` / `wezterm` / etc. work transparently.

Current tools (defined in `~/Code/bubblebox-pkgs/`):

- `age` — `age` from Fedora; standalone ad-hoc encryption (notably `age -d
  -i ~/.ssh/id_ed25519 nebula/pki/*.key.age` per repo convention). Not
  composed into `sops` — sops uses age as a Go library.
- `age-keygen` — a "virtual entrypoint" over the `age` package: its
  `entrypoint.toml` sets `package = "age"` + `binary = "age-keygen"`, so
  bubblebox execs `/usr/bin/age-keygen` from the age image rather than
  duplicating the build (no Containerfile of its own).
- `aws` — AWS CLI v2; config + credentials both live at the default `~/.aws/`
  (personal dotfiles + machine-local runtime state, reached via writable_home).
- `bat`, `dust`, `eza`, `rg`, `fd`, `tokei`, `htop` — CLI tools, Rust ones
  built via `cargo install` against a distroless runtime.
- `sops` — Mozilla SOPS, built from Go source (not packaged in Fedora) via
  `go install` against a distroless/static runtime. Edit mode (`sops
  file.yaml`) needs an editor override; see `sops/entrypoint.toml`.
- `nvim` — neovim; config lives in dotfiles (`~/.config/nvim`), plugin trees +
  undo history isolated to `/persist` (bound from `$BUBBLEBOX_DATA_DIR/nvim`).
- `wezterm`, `ghostty` — GUI terminals; spawn the host shell via
  `systemd-run --user` so the shell inside the terminal has full host access
  (PATH, `/dev/fuse`, host tools, etc.).
- `vicinae` — launcher daemon; bubblebox wrapper with GPU + D-Bus access via
  its entrypoint. Fallback launcher — the primary desktop shell is our
  niri-caelestia-shell fork, which ships in the host image (see
  `host-image/README.md`).
- `yazi`, `zoxide` — file manager and `cd` replacement.

(AI coding agents are not bubblebox tools — see the note where the hermes
section used to be.)

Typical workflow:

```bash
cjust bubblebox-apply          # realize the committed lock (idempotent)
cjust bubblebox-upgrade        # take new CI builds; commit profile.lock after
nvim ~/any/file                # wrapper at ~/.local/bin/nvim -> bubblebox run nvim
```

To add a new bubblebox tool: drop a `<name>/` subdir with a `Containerfile`
(and, if it needs binds/env, an `entrypoint.toml`) in `~/Code/bubblebox-pkgs/`,
open a PR (CI verifies it; dispatch `publish.yml` after merge to push it to the
cache), then add the name to `bubblebox/profile.toml`'s `packages` list and run
`cjust bubblebox-upgrade`. To try a Containerfile before the PR, `cjust
bubblebox-build <name>` builds it locally.

(AI coding agents are not bubblebox tools — opencode was retired
2026-09-02, and the hermes desktop + dsh CLI were removed from this host
2026-10-16 (unused here). Agent work happens on bee via the dsh web UI at
`https://dsh.internal.crussell.io`.)
### Host-resident dotfiles (`bubblebox/files/` + `[[files]]`)

Host-native user dotfiles — the small exception to "everything lives in a
sandbox." A tool's personal config (e.g. `~/.aws/config`,
`~/.config/vicinae/`, `~/.config/nvim`) lives under `bubblebox/files/`
(mirroring `$HOME`-relative layout) and is declared in the `[[files]]` section
of `bubblebox/profile.toml`. `bubblebox apply` hashes each file's content into
the content-addressed store and symlinks `$HOME/<dst>` → the store blob, so the
checkout is the single source of truth. A few things are inherently
host-resident regardless:

- **oh-my-posh** — renders the prompt on every command, can't pay a
  per-invocation sandbox spawn

This is declarative, not live-edit: change the source file under
`bubblebox/files/` and re-run `cjust bubblebox-apply` to re-link. No
templating, no secrets, no dotfiles manager. (For `kind = "dir"` entries like
`.config/nvim`, `bubblebox apply` walks the tree into per-file store symlinks;
user-owned files inside managed dirs are never touched.)

```bash
# set up / refresh all host-native dotfiles (idempotent, part of the profile)
cjust bubblebox-apply
```

To add another host-native dotfile: drop it under `bubblebox/files/` at its
`$HOME`-relative path, add a `[[files]]` entry (with `dst = "<path>"`) to
`bubblebox/profile.toml`, and re-run `cjust bubblebox-apply`. Secrets stay on
the existing rails (agenix/age, see the repo-wide `AGENTS.md`) — don't add them
here.

#### COSMIC desktop settings — `bubblebox/files/.config/cosmic/`

The entire COSMIC settings tree is vendored under
`bubblebox/files/.config/cosmic/` and managed via **copy**, not bubblebox
symlinks — COSMIC dislikes symlinks for its config tree, so this is a permanent
exception. `cjust cosmic-backup` copies the live `~/.config/cosmic` into the
repo tree for git tracking, and `cjust cosmic-restore` copies it back. It
covers the compositor (`com.system76.CosmicComp`), panels + dock, themes
(dark/light), applets (time, audio, battery), terminal, files, app
library/list, and shortcuts.

`cosmic-config` persists each key as a **plain-text, RON-like file** under
`<app>/v1/<key>`, which makes the tree:

- **git-friendly** — every change is a readable diff.
- **LLM-editable** — an agent can read a key, edit it, and the live setting
  updates on cosmic's next config reload (or session restart).
- **portable** — no `/home/` paths, UUIDs, or machine IDs; the wallpaper
  points at a path shipped with COSMIC itself.

Notes:

- Settings for a **newly installed** COSMIC app are captured by re-running
  `cjust cosmic-backup` (it copies the whole live tree into the repo). If an
  app starts emitting runtime **state** rather than settings, add its subdir
  to a `.gitignore` under `bubblebox/files/.config/cosmic/`.
- On a fresh machine, `cjust cosmic-restore` copies the repo tree over
  `~/.config/cosmic` (after removing any pre-existing dir or stale symlink),
  so replication is one command.
- COSMIC reads most keys on the fly; a few (compositor bindings, themes) need
  a session restart to fully apply after an edit.

### Systemd user units (`bubblebox/units/` + `[[units]]`)

Systemd units, mostly **user** services, now declared in the `[[units]]` section
of `bubblebox/profile.toml` with sources under `bubblebox/units/`. `bubblebox
apply` symlinks each unit into `~/.config/systemd/user/`, daemon-reloads, and
enables lingering; units with `enable = true` in the profile are also started.
Current units:

- `vicinae.service` — starts the bubblebox-wrapped vicinae launcher daemon
  (`vicinae server --replace`), bound to `graphical-session.target` so it
  auto-starts under any compositor (niri, COSMIC, ...) — replacing niri's
  `spawn-at-startup`. The `Mod+Space { spawn "vicinae" "toggle"; }` client
  keybind in niri is unaffected (it's an IPC client, not the daemon).

```bash
cjust bubblebox-apply
# then enable/start a specific unit (if not auto-enabled via `enable = true`):
systemctl --user enable --now vicinae
```

Adding a unit: drop `<name>.service` in `bubblebox/units/`, add a `[[units]]`
entry (`name = "<name>"`, optionally `enable = true`) to
`bubblebox/profile.toml`, and re-run `cjust bubblebox-apply`.

## State philosophy

Prefer explicit state roots over accidental host drift.

Examples:

- `~/Code` for deliberate work
- `~/.var/app/` for Flatpak state
- bubblebox storage: `~/.local/share/bubblebox/` (descriptors, content store,
  per-tool persistent state like nvim's plugins/parsers) and
  `/run/user/$UID/bubblebox/` (FUSE mountpoints, ephemeral per-session)

## Notes

- `host-image/` ships the desktop stack: niri (compositor) + our
  niri-caelestia-shell fork (desktop shell, built at a pinned commit), plus
  the small set of host-resident tools (just, fzf, nodejs/npm for the
  npm-managed dev CLIs).
- Dev tools live in bubblebox sandboxes, not on the host image.
- AI coding agents don't run on this host. (opencode was retired 2026-09-02;
  the hermes desktop and dsh CLI were removed 2026-10-16 — agent work happens
  on bee via the dsh web UI.)

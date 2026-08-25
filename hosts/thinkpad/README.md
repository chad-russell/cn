# ThinkPad — atomic workstation repo

This repo holds machine-specific infrastructure for a Fedora-based atomic (bootc)
host.

## Main projects here

```text
.
├── host-image/     # minimal bootc host image
├── nebula/         # Nebula VPN container/service
├── backup/         # restic S3 backup Quadlet + timers (daily backup, weekly check)
├── wycliffe-vpn/   # on-demand GlobalProtect wrapper
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
cjust setup            # full first-run: bubblebox (tools + dotfiles + units) + opencode
cjust bubblebox        # build FUSE server + all tool images + apply profile
cjust bubblebox-apply  # (re)apply the profile: dotfiles + units + package wrappers
cjust status           # show host-image / bootc / bubblebox / opencode state
cjust -l               # list all recipes
```

Dotfiles and systemd user units are declared in `bubblebox/profile.toml` (the
`[[files]]` and `[[units]]` sections) and realized by `cjust bubblebox-apply`.
`cjust link` and `cjust units` are retired — the declarative profile is the
single source of truth.

## Current architecture

### `host-image/`
A minimal bootc-managed host image. It is intentionally small: host-level
choices that truly belong in the base OS (convenience packages, disabling
SELinux, removing `toolbox`, adding `distrobox`, the compositors, and
`nodejs`/`npm` so `cjust opencode-install` works). See `host-image/README.md`.

The image is built **on bees** (daily `thinkpad-image-build.timer` + on-demand
`cjust image-rebuild`) and published to bees's zot registry
(`10.10.0.6:5000/cn/thinkpad-host:44`, Nebula-only). `cjust image-upgrade`
pulls only the changed layers and stages the new deployment; it goes live on
the next reboot. Local `./build.sh` remains as the break-glass path. See
`hosts/bees/thinkpad-registry.nix` for the registry + build service.

### `nebula/`
Rootful Podman/Quadlet-based Nebula VPN setup.

### `wycliffe-vpn/`
On-demand Wycliffe GlobalProtect container workflow. See
`wycliffe-vpn/README.md`.

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

bubblebox auto-mounts each tool on first invocation (rootless FUSE) — no
separate prepare/mount step. `cjust bubblebox` builds the images and
`bubblebox apply` materializes the profile, generating wrappers at
`~/.local/bin/<tool>`, then `nvim` / `aws` / `wezterm` / etc. work transparently.

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
- `noctalia`, `vicinae` — desktop shell + launcher; daemon+client model with
  GPU + `/sys` + D-Bus access via their entrypoints.
- `yazi`, `zoxide` — file manager and `cd` replacement.

`opencode` is intentionally NOT a bubblebox tool — it's an AI agent and needs
full host control (spawning subprocesses in arbitrary cwds with synchronous
I/O capture has no precedent in the bubblebox tree and fights the sandbox's
read-only / content-addressed model). It's installed directly on the host via
`cjust opencode-install`. (Hermes used to be in the same category; its agent
now lives on bee and only the desktop GUI runs here — see the `hermes/`
section below.)

Typical workflow:

```bash
cjust bubblebox                # build images + apply profile (idempotent)
nvim ~/any/file                # wrapper at ~/.local/bin/nvim -> bubblebox run nvim
```

To add a new bubblebox tool: drop a `<name>/` subdir with a `Containerfile`
(and, if it needs binds/env, an `entrypoint.toml`) in `~/Code/bubblebox-pkgs/`,
add the name to `bubblebox/profile.toml`'s `packages` list, and re-run
`cjust bubblebox`.

### `hermes/` (desktop-only; agent lives on bee)

[Hermes Agent](https://hermes-agent.nousresearch.com/) (Nous Research) — the AI
agent with a CLI, TUI (`hermes --tui`), and Electron desktop app. The AGENT is
not installed on this host — it runs on bee as a NixOS service (deployed from
this flake), and this laptop is a thin client: the desktop app connects to bee
over SSH and spawns `hermes serve` there. All state (config, sessions, skills,
memory) lives on bee.

```bash
cjust hermes-desktop-build     # build the Electron app off-host, extract to host
cjust hermes-desktop-build main  # …or build a specific rev (default: latest release tag)
~/.local/bin/hermes-desktop    # launch via the host wrapper
```

No local `hermes` install is needed. `~/.hermes/` on this host is still used
by the desktop app itself (logs, plugins, desktop-plugins) — don't delete it,
but it holds no agent state that matters.

**How updates work.** The build maintains its own source checkout at
`~/.local/share/hermes-desktop-src` (a git clone of upstream). Each run
fetches and checks out the latest release tag by default. Upstream ships no
prebuilt desktop binaries — build-from-source is the only channel. Keep the
desktop roughly in step with bee's hermes version (the desktop warns when the
remote backend is older/newer than itself).

**Why the desktop is built off-host.** `hermes desktop` builds the Electron
app from source via npm, which needs `gcc-c++ make` + ~200 MB of `node_modules`
+ the Electron runtime download. None of that should land on the read-only
`/usr` host image (it would force a rebuild + reboot, and the host would carry
build cruft forever). Instead, `cjust hermes-desktop-build` follows the
`cjust icons` (Papirus) pattern: build inside a throwaway Fedora+Node podman
container, then copy only the unpacked app dir to
`~/.local/share/hermes-desktop/`. No host-image change, no reboot.

**Why not bubblebox for the GUI.** The *rendering* of an Electron window fits
bubblebox fine (same surface as wezterm/ghostty: `writable_run` + `/dev`
dev-bind + mesa). What doesn't fit is a local *agent backend*: it spawns
synchronous subprocesses in arbitrary host working directories dozens of times
per task, capturing stdout/stderr/exit. Since the agent lives on bee, that
concern is moot here — but the build also runs on the host (git + podman
only), and the app dir is per-user state, so bubblebox has nothing to manage.

**Secrets.** None needed locally — the desktop talks to bee over SSH and the
provider keys live on bee. Legacy: `secrets/hermes-thinkpad-env.age` fed a
former local agent install via `bubblebox/files/.zshenv`; the desktop wrapper
(`bubblebox/files/.local/bin/hermes-desktop`) still sources that cache before
exec'ing the Electron app, so a local agent could be re-added without a
wrapper change.

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
- **opencode** config — the agent runs on the host directly (see `cjust
  opencode-install`), so its config lives with the rest of the host dotfiles;
  auth stays at the default `~/.local/share/opencode/auth.json` (machine-local,
  gitignored by virtue of being outside this tree)

This is declarative, not live-edit: change the source file under
`bubblebox/files/` and re-run `cjust bubblebox-apply` to re-link. No
templating, no secrets, no dotfiles manager. (For `kind = "dir"` entries like
`.config/nvim`, `bubblebox apply` walks the tree into per-file store symlinks;
user-owned files inside managed dirs — e.g. opencode's `auth.json` — are never
touched.)

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

- `opencode-web.service` — runs the opencode web frontend. opencode is
  host-installed (via `cjust opencode-install`), so the unit just calls
  `opencode web --port 4096` directly — no sandbox or composefs mount
  dependency.
- `vicinae.service` — starts the bubblebox-wrapped vicinae launcher daemon
  (`vicinae server --replace`), bound to `graphical-session.target` so it
  auto-starts under any compositor (niri, COSMIC, ...) — replacing niri's
  `spawn-at-startup`. The `Mod+Space { spawn "vicinae" "toggle"; }` client
  keybind in niri is unaffected (it's an IPC client, not the daemon).

```bash
cjust bubblebox-apply
# then enable/start a specific unit (if not auto-enabled via `enable = true`):
systemctl --user enable --now opencode-web
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
- `~/.local/share/opencode/` for opencode runtime state (auth, db, logs)

## Notes

- `host-image/` is intentionally lean; the compositors (niri + COSMIC) ship in
  it, plus the small set of host-resident tools (just, fzf, oh-my-posh,
  nodejs/npm for opencode).
- Dev tools live in bubblebox sandboxes, not on the host image.
- opencode is the exception: it's installed on the host because it's an AI
  coding agent and needs full host control when something breaks (npm global
  via `cjust opencode-install`). The hermes agent is NOT installed here — it
  lives on bee, and this host runs only the desktop GUI, built off-host by
  `cjust hermes-desktop-build` from our own source checkout (~/.local/share/
  hermes-desktop-src). It's per-user, iterates on its own update channel, and
  doesn't deserve an image rebuild + reboot cycle.

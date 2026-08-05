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
├── bubblebox/      # the host's bubblebox profile.toml (desired package set)
├── dotfiles/       # the rare host-native user dotfiles (linked by cjust)
└── systemd/        # user/systemd units (mostly user services for now)
```

## Guiding principle

Keep the host small and explicit.

- host OS changes belong in `host-image/`
- apps and dev tools should prefer bubblebox sandboxes, Flatpaks, or other
  isolated models over being layered onto the host
- persistent mutable state should live in obvious, named locations
- the rare dotfile that must live host-native (e.g. oh-my-posh, which runs on
  every prompt render and so can't pay a per-invocation sandbox spawn) is
  tracked under `dotfiles/` and symlinked into `$HOME` by `cjust link`

## Task runner: `cjust`

`cjust` is the single entry point for setting up and maintaining this machine.
It's a thin wrapper (defined in `dotfiles/.zshrc`) around the task runner
`just`, pointing at `hosts/thinkpad/Justfile`. `just` and `fzf` are baked into
the host image so it works before any sandbox is set up.

```bash
cjust              # fuzzy recipe chooser (just --choose)
cjust setup        # full first-run: dotfiles + units + bubblebox + opencode
cjust link         # (re)symlink host-native dotfiles into $HOME
cjust units        # (re)symlink systemd user units + enable lingering
cjust bubblebox    # build FUSE server + all tool images + export wrappers
cjust status       # show host-image / bootc / bubblebox / opencode state
cjust -l           # list all recipes
```

Adding a new bubblebox tool, user unit, or dotfile is a one-line edit to a
data table at the top of the Justfile.

## Current architecture

### `host-image/`
A minimal bootc-managed host image. It is intentionally small: host-level
choices that truly belong in the base OS (convenience packages, disabling
SELinux, removing `toolbox`, adding `distrobox`, the compositors, and
`nodejs`/`npm` so `cjust opencode-install` works). See `host-image/README.md`.

### `nebula/`
Rootful Podman/Quadlet-based Nebula VPN setup.

### `wycliffe-vpn/`
On-demand Wycliffe GlobalProtect container workflow. See
`wycliffe-vpn/README.md`.

### `bubblebox/`
The host's **bubblebox profile** (`profile.toml`) — the desired set of bubblebox
tools to install, plus the source registry it resolves them from. This is the
`flake.nix` analog: a declarative input list that `bubblebox apply` realizes
into a pinned generation (`profile.lock`). It's the only bubblebox file that is
host-specific, so it lives here alongside the rest of the host config.

bubblebox itself spans three repos / concerns:

| concern | location | holds |
|---|---|---|
| **engine** | `~/Code/bubblebox` | the Rust CLI + FUSE server (`bubblebox build/run/apply/...`) |
| **packages** | `~/Code/bubblebox-pkgs` | per-tool `Containerfile` + `entrypoint.toml` (the nixpkgs-analog source) |
| **profile** | this dir (`bubblebox/profile.toml`) | the host's desired package set + source registration |

A **package** is an OCI image (a `Containerfile`); an **entrypoint** is how
bubblebox runs it (which binary to exec, what to compose in, binds/env) —
authored alongside the Containerfile because the package author knows what the
tool needs. **Config / dotfiles** are a separate concern: every tool reads its
personal config from the host `$HOME` via `writable_home` (e.g. aws reads
`~/.aws/config`, vicinae reads `~/.config/vicinae/`, nvim reads
`~/.config/nvim`), tracked under `dotfiles/` below. Runtime state that's
regenerable (nvim's plugin tree + undo history, zoxide's db) is isolated to
bubblebox-owned dirs via `/persist` binds.

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

`opencode` and `hermes` are intentionally NOT bubblebox tools — they're AI
agents and need full host control (spawning subprocesses in arbitrary cwds
with synchronous I/O capture has no precedent in the bubblebox tree and fights
the sandbox's read-only / content-addressed model). They're installed directly
on the host via `cjust opencode-install` / `cjust hermes-install`. See below.

Typical workflow:

```bash
cjust bubblebox                # build images + apply profile (idempotent)
nvim ~/any/file                # wrapper at ~/.local/bin/nvim -> bubblebox run nvim
```

To add a new bubblebox tool: drop a `<name>/` subdir with a `Containerfile`
(and, if it needs binds/env, an `entrypoint.toml`) in `~/Code/bubblebox-pkgs/`,
add the name to `bubblebox/profile.toml`'s `packages` list, and re-run
`cjust bubblebox`.

### `hermes/` (host-installed CLI/TUI/Desktop)

[Hermes Agent](https://hermes-agent.nousresearch.com/) (Nous Research) — the AI
agent with a CLI, TUI (`hermes --tui`), and Electron desktop app. Same category
as opencode (AI coding agent needing full host control), so it's host-installed
by the official installer, NOT a bubblebox tool. The desktop app's *build* is
off-host (see below), but the running agent lives on the host.

```bash
cjust hermes-install           # curl|bash installer -> ~/.local/bin/hermes
hermes --tui                   # TUI launches; installer self-manages Python+Node
cjust hermes-desktop-build     # build the Electron app off-host, extract to host
hermes desktop --skip-build    # launch via the upstream launcher
~/.local/bin/hermes-desktop    # …or the host wrapper (sources cn-secrets first)
```

The three surfaces (CLI, TUI, Desktop) are the same `hermes` binary driving
the same agent — all share state at `~/.hermes/` (config, sessions, skills,
memory, `.env`).

**Why the desktop is built off-host.** `hermes desktop` builds the Electron
app from source via npm, which needs `gcc-c++ make` + ~200 MB of `node_modules`
+ the Electron runtime download. None of that should land on the read-only
`/usr` host image (it would force a rebuild + reboot, and the host would carry
build cruft forever). Instead, `cjust hermes-desktop-build` follows the
`cjust icons` (Papirus) pattern: build inside a throwaway Fedora+Node podman
container via `hermes desktop --build-only`, then copy only the unpacked app
dir to `~/.local/share/hermes-desktop/`. No host-image change, no reboot.

**Why not bubblebox for the GUI.** The *rendering* of an Electron window fits
bubblebox fine (same surface as wezterm/ghostty: `writable_run` + `/dev`
dev-bind + mesa). What doesn't fit is the *agent backend*: it spawns
synchronous subprocesses in arbitrary host working directories dozens of times
per task, capturing stdout/stderr/exit. The only host-escape primitives in the
bubblebox tree are `bubblebox-host-shell` (interactive `--pty`) and
`vicinae-launch` (fire-and-forget, no `--wait`) — neither is the right shape
for programmatic subprocess exec, and the read-only rootfs fights
`hermes update`. The clean split is: agent backend on host (like opencode),
desktop GUI host-built.

**Secrets.** Provider keys live in `secrets/hermes-thinkpad-env.age` (agenix),
which exports `OPENAI_API_KEY` (the Z.AI coding key, remapped for hermes'
OpenAI-compatible provider resolver — same key value as `zai-api-key.age`).
`dotfiles/.zshenv` decrypts it alongside `zai-api-key.age` into per-login
tmpfs, so every shell (and any CLI/TUI invocation) sees the key. The desktop
wrapper (`dotfiles/.local/bin/hermes-desktop`) sources the same cache before
exec'ing the Electron app, so compositor-launched GUI sees it too (`.zshenv`
alone wouldn't — GUI apps read the systemd session env, not the shell env).

First-time provider config (after `cjust hermes-install`): point hermes at the
Z.AI coding endpoint by declaring a custom OpenAI-compatible provider in
`~/.hermes/config.yaml`:

```bash
hermes config set custom_providers '[{name:zai-coding,base_url:https://api.z.ai/api/coding/paas/v4,key_env:OPENAI_API_KEY}]'
hermes config set model.provider zai-coding
hermes config set model.default glm-5.2
hermes doctor   # verify deps + provider config
```

### `dotfiles/`
Host-native user dotfiles — the small exception to "everything lives in a
sandbox." A tool's personal config (e.g. `~/.aws/config`, `~/.config/vicinae/`,
`~/.config/nvim`) lives here and is reached at runtime via `writable_home`. A
few things are inherently host-resident regardless:

- **oh-my-posh** — renders the prompt on every command, can't pay a
  per-invocation sandbox spawn
- **opencode** config (`opencode.json`) — the agent runs on the host directly
  (see `cjust opencode-install`), so its config lives with the rest of the
  host dotfiles; auth stays at the default `~/.local/share/opencode/auth.json`
  (machine-local, gitignored by virtue of being outside this tree)

This directory mirrors `$HOME`-relative layout. Files are delivered by
symlink, not copied, so edits land in the repo live and the checkout is the
single source of truth. No templating, no secrets, no dotfiles manager.

```bash
# set up / refresh all host-native dotfile symlinks (idempotent)
cjust link
```

To add another host-native dotfile: drop it under `dotfiles/` at its
`$HOME`-relative path, add the path to the `dotfiles` list at the top of
`hosts/thinkpad/Justfile`, and re-run `cjust link`. Secrets stay on the
existing rails (agenix/age, see the repo-wide `AGENTS.md`) — don't add them
here.

#### COSMIC desktop settings — `dotfiles/.config/cosmic/`

The entire COSMIC settings tree is vendored here and symlinked as one
directory (`dotfiles/.config/cosmic` → `~/.config/cosmic`). It covers the
compositor (`com.system76.CosmicComp`), panels + dock, themes (dark/light),
applets (time, audio, battery), terminal, files, app library/list, and
shortcuts.

`cosmic-config` persists each key as a **plain-text, RON-like file** under
`<app>/v1/<key>`, which makes the tree:

- **git-friendly** — every change is a readable diff.
- **LLM-editable** — an agent can read a key, edit it, and the live setting
  updates on cosmic's next config reload (or session restart).
- **portable** — no `/home/` paths, UUIDs, or machine IDs; the wallpaper
  points at a path shipped with COSMIC itself.

Notes:

- Settings for a **newly installed** COSMIC app land in the repo
  automatically (they're written through the symlink). If an app starts
  emitting runtime **state** rather than settings, add its subdir to a
  `.gitignore` under `dotfiles/.config/cosmic/`.
- On a fresh machine, `cjust link` backs up any pre-existing
  `~/.config/cosmic` to `~/.config/cosmic.bak.<ts>` and symlinks the repo
  tree in its place, so replication is one command.
- COSMIC reads most keys on the fly; a few (compositor bindings, themes)
  need a session restart to fully apply after an edit.

### `systemd/`
Systemd units, mostly **user** services for now (`systemd/user/`). Current units:

- `opencode-web.service` — runs the opencode web frontend. opencode is
  host-installed (via `cjust opencode-install`), so the unit just calls
  `opencode web --port 4096` directly — no sandbox or composefs mount
  dependency.
- `vicinae.service` — starts the bubblebox-wrapped vicinae launcher daemon
  (`vicinae server --replace`), bound to `graphical-session.target` so it
  auto-starts under any compositor (niri, COSMIC, ...) — replacing niri's
  `spawn-at-startup`. The `Mod+Space { spawn "vicinae" "toggle"; }` client
  keybind in niri is unaffected (it's an IPC client, not the daemon).

To install every unit (symlink into `~/.config/systemd/user/`, daemon-reload,
and enable lingering):

```bash
cjust units
# then enable the specific unit(s):
systemctl --user enable --now opencode-web
systemctl --user enable --now vicinae
```

Adding a unit: drop `<name>.service` in `systemd/user/`, add the name (without
`.service`) to the `user_units` list at the top of `hosts/thinkpad/Justfile`,
and re-run `cjust units`.

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
- opencode and hermes are the exceptions: they're installed on the host
  because they're AI coding agents and need full host control when something
  breaks. opencode lands via `cjust opencode-install` (npm global); hermes
  lands via `cjust hermes-install` (official installer) + `cjust
  hermes-desktop-build` (off-host Electron build). Hermes's desktop build
  stays off the host image on purpose — it's per-user, iterates on its own
  update channel, and doesn't deserve an image rebuild + reboot cycle.

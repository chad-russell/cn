# ThinkPad — atomic workstation repo

This repo holds machine-specific infrastructure for a Fedora-based atomic (bootc)
host.

## Main projects here

```text
.
├── host-image/     # minimal bootc host image
├── nebula/         # Nebula VPN container/service
├── wycliffe-vpn/   # on-demand GlobalProtect wrapper
├── bubblebox/      # vendored per-tool configs for bubblebox sandboxes
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
Vendored per-tool configs for **bubblebox** sandboxes. Each subdir holds a
`Containerfile` and (optionally) a `profile` of bubblewrap overrides for that
tool. bubblebox source lives in a separate repo at `~/Code/bubblebox` (the
`bubblebox-{init,build,mount,run,export}` scripts plus the FUSE server); this
directory holds only the per-tool definitions, version-controlled alongside
the rest of the host config.

bubblebox auto-mounts each tool on first invocation (rootless FUSE), so there's
no separate prepare/mount step — `cjust bubblebox` builds the images and
generates wrapper scripts at `~/.local/bin/<tool>`, then `nvim` / `aws` /
`wezterm` / etc. work transparently.

Current tools:

- `aws/` — AWS CLI v2; non-secret `config` vendored into the image, credentials
  and SSO cache remain at default `~/.aws/` (runtime, machine-local)
- `bat/`, `dust/`, `eza/`, `rg/`, `fd/`, `tokei/`, `htop/` — CLI tools,
  Rust ones built via `cargo install` against a distroless runtime
- `nvim/` — self-contained neovim (vendored config + isolated state via
  `/persist` bind from `$BUBBLEBOX_DATA_DIR/nvim`)
- `wezterm/` — GUI terminal; spawns the host shell via `systemd-run --user`
  so the shell inside the terminal has full host access (PATH, `/dev/fuse`,
  host tools, etc.)
- `noctalia/`, `vicinae/` — desktop shell + launcher; same daemon+client model
  as their predecessors, with GPU + `/sys` + D-Bus access via the profile
- `yazi/`, `zoxide/` — file manager and `cd` replacement

`opencode` is intentionally NOT a bubblebox tool — it's the AI coding agent and
needs full host control, so it's installed directly via `cjust opencode-install`
(see below).

Typical workflow:

```bash
cjust bubblebox                # build + export all tools (idempotent)
nvim ~/any/file                # wrapper at ~/.local/bin/nvim -> bubblebox-run
bubblebox-mount wezterm        # pre-warm a tool's FUSE mount (optional)
bubblebox-unmount wezterm      # tear down (rarely needed; auto-tears on reboot)
```

To add a new bubblebox tool: drop a `<name>/` subdir with a `Containerfile`
(and optionally a `profile`) under `bubblebox/`, add the name to the
`bubblebox_tools` list at the top of the Justfile, and re-run `cjust bubblebox`.

### `dotfiles/`
Host-native user dotfiles — the small exception to "everything lives in a
sandbox." Almost every tool's config rides along with its bubblebox image
(e.g. `bubblebox/nvim/config/`), because the binary runs from the sandbox. A
few things are inherently host-resident:

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
- opencode is the one exception: it's installed on the host because it's the
  AI coding agent and needs full host control when something breaks.

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
├── dotfiles/       # the rare host-native user dotfiles (linked by cjust)
└── systemd/        # user/systemd units (mostly user services for now)
```

## Guiding principle

Keep the host small and explicit.

- host OS changes belong in `host-image/`
- desktop sessions belong in `desktoppak/`
- apps and dev tools should prefer shellboxes, Flatpaks, or other isolated
  models over being layered onto the host
- persistent mutable state should live in obvious, named locations
- the rare dotfile that must live host-native (e.g. oh-my-posh, which runs on
  every prompt render and so can't live in a shellbox) is tracked under
  `dotfiles/` and symlinked into `$HOME` by `cjust link`

## Task runner: `cjust`

`cjust` is the single entry point for setting up and maintaining this machine.
It's a thin wrapper (defined in `dotfiles/.zshrc`) around the task runner
`just`, pointing at `hosts/thinkpad/Justfile`. `just` and `fzf` are baked into
the host image so it works before any shellbox is set up.

```bash
cjust              # fuzzy recipe chooser (just --choose)
cjust setup        # full first-run: dotfiles + units + shellboxes + boot mounts
cjust link         # (re)symlink host-native dotfiles into $HOME
cjust units        # (re)symlink systemd user units + enable lingering
cjust status       # show host-image / bootc / shellbox state
cjust -l           # list all recipes
```

Adding a new box, boot-mount, user unit, or dotfile is a one-line edit to a
data table at the top of the Justfile.

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

- `default/` — generic CLI tools (`htop`, `rg`, `fd`, `bat`, `eza`, `zoxide`, `wezterm`, `tokei`)
- `nvim/` — self-contained neovim (XDG dirs redirected into the box)
- `opencode/` — self-contained `sst/opencode` coding agent
- `aws/` — AWS CLI v2; non-secret `config` vendored into the box, credentials
  and SSO cache remain at default `~/.aws/` (runtime, machine-local)

Each self-contained box keeps all of its config/data/state/cache inside the box
directory (via absolute-literal XDG env redirection in `shellbox.toml`), so it
never touches `~/.config`, `~/.local/share`, etc. The `aws` box follows a
partial version of this pattern: only the (non-secret) AWS config is vendored,
since credentials and SSO tokens are short-lived runtime state that should be
re-obtained per machine rather than tracked in git.

Typical workflow:

```bash
shellbox link ~/Code/cn/hosts/thinkpad/shellboxes/nvim
shellbox build nvim
sudo shellbox mount nvim
shellbox export nvim nvim     # add ~/.local/share/shellbox/exports/bin to PATH once
nvim ~/any/file
```

See the `shellbox` README (`~/Code/cn/shellbox/README.md`) for the full tool.

### `dotfiles/`
Host-native user dotfiles — the small exception to "everything lives in a
shellbox." Almost every tool's config rides along with its shellbox (e.g.
`shellboxes/nvim/config/`), because the binary runs from the box. A few tools
are inherently host-resident — currently just **oh-my-posh** (it renders the
prompt on every command, so it can't pay a per-invocation bwrap spawn) — and
their config lives here instead.

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
Systemd units, mostly **user** services for now (`systemd/user/`), with room to
add system units later. The current unit, `opencode-web.service`, runs the
opencode web frontend as a user service by calling into the `opencode` shellbox
via `shellbox run`. The composefs mount it depends on is brought up at boot by
the `shellbox-mount@opencode.service` template baked into the host image. To
install every unit (symlink into `~/.config/systemd/user/`, daemon-reload, and
enable lingering):

```bash
cjust units
# then enable the specific unit:
systemctl --user enable --now opencode-web
```

Adding a unit: drop `<name>.service` in `systemd/user/`, add the name (without
`.service`) to the `user_units` list at the top of `hosts/thinkpad/Justfile`,
and re-run `cjust units`.

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

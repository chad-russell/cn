# shellbox

A lightweight devshell/container utility built around OCI images, composefs for
deduplicated read-only root filesystems, and `bwrap` for rootless command
execution.

The goal is named dev environments that feel like a nix devshell or Python
virtualenv — your shell, with extra tools — alongside a strict container-like
runtime when you want it.

---

## Build

```bash
cd /work/bw/shellbox
chmod +x build.sh
./build.sh
```

This builds inside a Rust container image via podman and copies the binary to:

```
target-host/shellbox
```

---

## Concepts

A **box** is a named dev environment with:

- a **source**: an OCI image (`--image`) or a co-located `Containerfile`
- build artifacts: an exported rootfs and a composefs image (`.cfs`)
- a **shell manifest**: the tools to surface from the box

Boxes are **immutable**. To change one, edit its source and rebuild.

### Single source of truth

Each box is **vendored** under `~/.local/share/shellbox/boxes/<name>/`, and its
`shellbox.toml` is the single source of truth — there is no separate stored
config. Editing the file is immediately effective; there is no snapshot or
"apply" step.

A box directory holds authored files only:

```
boxes/<name>/
  shellbox.toml      # the manifest — source of truth
  Containerfile      # optional; presence (with no `image`) => containerfile source
```

The box directory may be a **symlink** (e.g. into a dotfiles repo); see
[Dotfiles / version control](#dotfiles--version-control).

### Lifecycle

A box has three states:

1. **defined** — manifest exists, nothing built yet
2. **built** — composefs artifacts exist, can be mounted
3. **mounted** — composefs is mounted, can be used by `run` / `shell` / `enter`

Transitions are explicit and predictable:

```
create  -> defined
build   -> built
mount   -> mounted
unmount -> built
rm      -> removed
```

`run`, `shell`, and `enter` do **not** auto-build or auto-mount.

### Two workflows

shellbox supports two clearly distinct workflows:

**Devshell workflow** — host-shell first, tools surfaced into your shell:

- `shell` — open a nested shell with box tools added to `PATH`
- `export` — persistently install a box tool wrapper

**Runtime workflow** — box rootfs first, for debugging/strict execution:

- `run` — run one command inside the box runtime
- `enter` — open an interactive shell inside the box runtime

`run` and `enter` are runtime primitives; `shell` and `export` are thin tool
surfacing features built on top of `run`.

### Privilege model

Only `mount` and `unmount` require `sudo`. Everything else is rootless.

---

## Defining a box

### From the command line

```bash
shellbox create --name demo --image fedora:latest --tool rg --tool jq
```

For a containerfile-backed box, point `--file` at a Containerfile; it is copied
into the box directory as `Containerfile`:

```bash
shellbox create --name myproj --file ./Containerfile --tool rg
```

### From an external manifest (`--from`)

`--from` imports a box from an external file or directory and vendors it into
`boxes/<name>/`:

```bash
shellbox create --name demo --from /path/to/shellbox.toml
shellbox create --name demo --from /path/to/box-dir/
```

When given a directory, the entire directory is copied in (its `shellbox.toml`
becomes the manifest and any `Containerfile` comes along). This is the bridge
for keeping boxes in a dotfiles repo or sharing them.

If `--from` is omitted, shellbox auto-discovers `./shellbox.toml` in the current
directory (like `Cargo.toml`).

### The manifest format

`shellbox.toml`:

```toml
name = "demo"                      # optional; must match the box directory if set
image = "fedora:latest"            # mutually exclusive with a co-located Containerfile
# (or place a Containerfile next to this file and omit `image`)

[shell]
tools = ["rg", "jq"]

[shell.env]
# Plain string values — no token expansion.
FOO = "bar"
```

### Precedence

CLI flags override or append on top of an imported manifest:

- `--name` / `--image` / `--file` **override** manifest values
- `--tool` **appends** to the manifest's tools
- exactly one source (`image` or a Containerfile) is required across manifest
  and CLI

### Environment variables

You can declare env vars to set whenever the box is used (`run`, `shell`,
`enter`, or via `export`). Values are **plain strings** — there is no token
expansion. If you want to redirect a tool's state somewhere self-contained,
point the env var at an absolute path you choose:

```toml
[shell]
tools = ["nvim"]

[shell.env]
XDG_CONFIG_HOME = "/home/me/.local/share/shellbox/data/nvim/config"
```

Because values are literals, renaming or moving a box does not rewrite them —
update them yourself if they reference paths that changed.

---

## Commands

### `create`

Define a box by writing its manifest into `boxes/`.

```bash
shellbox create --name <name> --image <ref> [--tool <name>]... [--from <path>] [--force]
shellbox create --name <name> --file <path> [--tool <name>]... [--from <path>] [--force]
```

`--force` overwrites an existing box (refuses if mounted).

### `link`

Symlink an external authoring directory into `boxes/`, so edits land in the
source tree (e.g. a dotfiles repo). Unlike `create --from` (which copies),
`link` points at existing files.

```bash
shellbox link [<source>] [--name <name>] [--force]
```

`<source>` defaults to the current directory; the name defaults to the source
dir basename. The source is canonicalized to an absolute path before linking,
so relative paths won't dangle. `--force` overwrites an existing box (refuses
if mounted).

### `build`

Build composefs artifacts. Requires podman and `mkcomposefs`.

```bash
shellbox build <name>
```

### `list`

List all known boxes with live status.

```bash
shellbox list
```

### `inspect`

Show a box's source, shell tools, state, paths, and last-built time.

```bash
shellbox inspect <name>
```

### `mount` / `unmount`

Mount or unmount the composefs image. Require `sudo`.

```bash
sudo shellbox mount <name>
sudo shellbox unmount <name>
```

### `run`

Run one command inside the box runtime (rootfs-first). Exits with the command's
exit code.

```bash
shellbox run <name> -- <cmd> [args...]
```

### `shell` (devshell mode)

Open a nested host shell with declared tools surfaced as wrappers on `PATH`.
Exit with `exit` or `Ctrl-D` to return to your previous shell.

```bash
shellbox shell <name>
```

Inside, declared tools resolve to wrappers that invoke `shellbox run`. You are
still "you" — same home, cwd, prompt, git config, SSH agent, etc.

### `enter` (interactive runtime mode)

Open an interactive shell **inside the box runtime** (bwrap, box rootfs as `/`).
Useful for inspecting/debugging the box itself.

```bash
shellbox enter <name>
```

### `rm`

Remove a box's derived artifacts. The manifest is kept by default.

```bash
shellbox rm <name>                 # remove derived artifacts; keep manifest
shellbox rm <name> --purge         # also remove the manifest directory
shellbox rm <name> --purge --force # required to purge a symlinked box
```

Refuses if mounted. `--purge` on a symlinked box requires `--force` (the symlink
is removed; the target is left untouched). Note any exports that still
reference the box so you can clean them up.

### `rename`

Rename a box, moving its manifest, derived state, and updating its exports.

```bash
shellbox rename <old> <new>
```

Refuses if `<old>` is mounted or `<new>` already exists. Export wrappers owned
by the box are regenerated with the new name.

### `export`

Persistently install a host-side wrapper for a box tool. The wrapper invokes
`shellbox run <name> -- <tool> "$@"`.

```bash
shellbox export <name> <tool>
shellbox export <name> --all        # export every declared shell tool
shellbox export <name> <tool> --force
```

Exports live in a shellbox-owned directory so cleanup is easy:

```
~/.local/share/shellbox/exports/
  bin/        <- add this to your PATH
  metadata/   <- ownership records
```

Add it once to your shell rc:

```bash
export PATH="$HOME/.local/share/shellbox/exports/bin:$PATH"
```

Collision policy: exporting a name owned by another box fails unless `--force`
is given.

### `unexport`

Remove exported tool wrappers.

```bash
shellbox unexport <tool>                  # remove one
shellbox unexport --all                    # remove every export
shellbox unexport --all --box <name>       # remove all owned by a box
```

Removing a nonexistent export is idempotent (succeeds and reports nothing to
remove).

### `list-exports`

List all exported tools and the box that owns each.

```bash
shellbox list-exports
```

---

## Examples

### Image-backed box

```bash
shellbox create --name fedora-rg --image localhost/local/fedora-rg:latest --tool rg
shellbox build fedora-rg
sudo shellbox mount fedora-rg

shellbox run fedora-rg -- rg --version
shellbox shell fedora-rg        # nested host shell with rg on PATH
shellbox enter fedora-rg        # interactive shell inside box runtime

sudo shellbox unmount fedora-rg
```

### Containerfile-backed box

```bash
shellbox create --name myproj --file ./Containerfile
shellbox build myproj
sudo shellbox mount myproj
shellbox shell myproj
```

### Rename a box

```bash
shellbox rename myproj myproject
# manifest, build artifacts, mountpoint, and exports all follow
```

### Export a tool for use across shells

```bash
shellbox export fedora-rg --all
export PATH="$HOME/.local/share/shellbox/exports/bin:$PATH"
rg --version
```

---

## Dotfiles / version control

A box directory can be a symlink into a dotfiles repo. Use `shellbox link`
(canonicalizes the source to an absolute path for you, so you don't have to
remember the boxes-dir path or worry about dangling relative symlinks):

```bash
# from inside the box source dir (name derived from the dir)
shellbox link

# pointing elsewhere
shellbox link ~/dotfiles/shellboxes/nvim

# explicit name
shellbox link ~/dotfiles/shellboxes/nvim --name nvim
```

This is equivalent to a manual `ln -s <abs-source>
~/.local/share/shellbox/boxes/<name>`, and lets you version and share the
authored manifest (and any companion files like a Containerfile or bundled
config). Because derived build artifacts live
under `~/.local/state/shellbox/<name>/` — **not** in the box directory — nothing
machine-specific is written into your repo.

`rename` on a symlinked box renames the symlink entry under `boxes/`, not the
real file. `rm` without `--purge` is always safe (it never touches the symlink
or its target); `rm --purge` on a symlinked box requires `--force` and removes
only the symlink.

---

## Storage layout

```text
~/.local/share/shellbox/
  boxes/<name>/             # authored files only (may be a symlink)
    shellbox.toml           # manifest — single source of truth
    Containerfile           # present iff containerfile-backed
  store/                    # shared composefs digest store
  exports/
    bin/<tool>              # persistent tool wrappers (add to PATH)
    metadata/<tool>.json    # export ownership records

~/.local/state/shellbox/
  <name>/                   # all per-box derived state
    metadata.json           # build/mount cache (not authoritative)
    image.cfs               # composefs image
    rootfs/                 # exported rootfs (build input)
    mount/                  # composefs mountpoint
  sessions/                 # ephemeral devshell wrapper dirs
```

---

## How identity works

When you run or enter a box, tools like `whoami` and your shell prompt need to
resolve your username. shellbox solves this by **baking your user identity into
the rootfs at build time**: during `build`, your passwd/group entries are merged
into the rootfs's `/etc` (while it is still a normal writable directory), before
`mkcomposefs` freezes it into a read-only image.

Consequences:

- `whoami`, `id`, and prompt username all work inside `run` / `enter`
- zero runtime overhead — no temp dirs or overlays per invocation
- any image works; no Containerfile changes are required
- identity is per-user, matching the per-user storage model

Because identity is baked at build time, you must **rebuild** after changing the
user account (e.g. new uid/gid) for it to take effect.

### Desktop integration

The box runtime is **not** a hermetic desktop sandbox. By default `run` and
`enter` bind-mount your user runtime directory (`$XDG_RUNTIME_DIR`) and the X11
socket dir (`/tmp/.X11-unix`) into the box, so the host's **system clipboard**
(wl-clipboard, xclip/xsel), **D-Bus session bus**, **notifications**, **audio**,
and **xdg-desktop-portal** are all reachable from inside. This matches the
"your shell, with extra tools" goal: GUI/text editors (e.g. nvim) can yank to
the clipboard, GUI tools can open portals, etc., exactly as they would if
installed directly on the host.

On headless hosts, SSH sessions, or CI — where these paths don't exist — the
binds are skipped silently, so box behavior is unchanged.

This is the same trust boundary as `dnf install`-ing the tool onto the host: a
box binary that can talk to Wayland/D-Bus is no more privileged than any other
binary you'd run directly. If you ever want a stricter boundary for a specific
box, that's a future opt-in (a per-box sandbox flag), not the default.

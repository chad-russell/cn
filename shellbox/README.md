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

- a **source**: an OCI image (`--image`)
- composefs artifacts: an exported rootfs and a composefs image (`.cfs`)
- a **shell manifest**: the tools to surface from the box

Boxes are **immutable**. To change one, edit its manifest (and/or its
Containerfile) and re-prepare.

### Single source of truth

Each box is **vendored** under `~/.local/share/shellbox/boxes/<name>/`, and its
`shellbox.toml` is the single source of truth — there is no separate stored
config. Editing the file is immediately effective; there is no snapshot or
"apply" step.

A box directory holds authored files only:

```
boxes/<name>/
  shellbox.toml      # the manifest — source of truth
```

The box directory may be a **symlink** (e.g. into a dotfiles repo); see
[Dotfiles / version control](#dotfiles--version-control).

### Lifecycle

A box has two states:

1. **defined** — manifest exists, nothing prepared yet
2. **prepared** — composefs artifacts exist, can be used

Transitions are explicit and predictable:

```
create  -> defined
prepare -> prepared
rm      -> removed
```

`run` and `shell` do **not** auto-prepare. They mount the composefs image
rootlessly (via FUSE) on demand, for the duration of each command.

### Two workflows

shellbox supports two clearly distinct workflows:

**Devshell workflow** — host-shell first, tools surfaced into your shell:

- `shell` — open a nested shell with box tools added to `PATH`
- persistent **exports** — wrappers for declared tools, synced automatically by
  `prepare` into a directory on your `PATH`

**Runtime workflow** — box rootfs first, for debugging/strict execution:

- `run` — run one command inside the box runtime, or open an interactive shell
  when no command is given

`run` is the runtime primitive; `shell` and the export wrappers are thin tool
surfacing features built on top of `run`.

### Privilege model

**Nothing requires `sudo`.** `run` and `shell` mount the composefs image via a
fully rootless FUSE runtime (a private user + mount namespace, with a
background FUSE server thread) for the duration of each command. No persistent
host mount is created, and nothing runs as root. shellbox is rootless
end-to-end.

---

## Defining a box

### From the command line

```bash
shellbox create --name demo --image fedora:latest --tool rg --tool jq
```

### From an external manifest (`--from`)

`--from` imports a box from an external file or directory and vendors it into
`boxes/<name>/`:

```bash
shellbox create --name demo --from /path/to/shellbox.toml
shellbox create --name demo --from /path/to/box-dir/
```

When given a directory, the entire directory is copied in (its `shellbox.toml`
becomes the manifest). This is the bridge for keeping boxes in a dotfiles repo
or sharing them.

If `--from` is omitted, shellbox auto-discovers `./shellbox.toml` in the current
directory (like `Cargo.toml`).

### The manifest format

`shellbox.toml`:

```toml
name = "demo"                      # optional; must match the box directory if set
image = "fedora:latest"            # OCI image reference the box is materialized from

[shell]
tools = ["rg", "jq"]

[host]
tools = ["podman"]                 # host tools (see "Host tools" below)

[shell.env]
# Plain string values — no token expansion.
FOO = "bar"

# Extra bind mounts, layered after shellbox's fixed binds (see below).
[[binds]]
host = "/sys"
guest = "/sys"
mode = "ro"          # ro (default) | rw | dev
optional = true      # use the -try variant; skip silently if absent
```

### Building the image from a Containerfile

If a `Containerfile` (or `Dockerfile`) sits next to `shellbox.toml` in the box
directory, `prepare` builds it into the manifest's `image` reference before
materializing the rootfs:

```bash
shellbox prepare <name>     # builds the Containerfile (if present), then materializes
```

This lets a box be fully self-contained: the manifest declares the tools/env,
the Containerfile declares how the image is built, and a single `prepare` makes
both active. The box directory is the build context, so companion files next to
the manifest are visible to the build (you can `COPY` them).

The `image` field is still **required** — the Containerfile is built and tagged
*into* that ref. Podman's layer cache makes an unchanged Containerfile a
near-instant no-op, so re-running `prepare` to pick up a manifest edit doesn't
needlessly rebuild the image. Vendoring works as usual: `create --from <dir>`
copies a Containerfile along with the manifest, and `link` symlinks it.

### Precedence

CLI flags override or append on top of an imported manifest:

- `--name` / `--image` **override** manifest values
- `--tool` **appends** to the manifest's tools
- an `image` is required (from the manifest, `--image`, or `--from`)

### Environment variables

You can declare env vars to set whenever the box is used (`run`, `shell`,
or via persistent exports). Values are **plain strings** — there is no token
expansion. If you want to redirect a tool's state somewhere self-contained,
point the env var at an absolute path you choose:

```toml
[shell]
tools = ["nvim"]

[shell.env]
XDG_CONFIG_HOME = "/home/me/.local/share/shellbox/data/nvim/config"
```

Because values are literals, moving a box does not rewrite them —
update them yourself if they reference paths that changed.

### Host tools

A box's read-only composefs rootfs cannot host tools that need the live host
(e.g. `podman`, `flatpak`, `rpm-ostree`). Declare them in the `[host]` table
and they become transparently callable from inside `run`:

```toml
[host]
tools = ["podman", "flatpak"]
```

Then, inside the box:

```bash
shellbox run demo -- podman ps     # works, even though podman is not in the box
```

How it works — **no daemon, no parent-side bridge, no second binary**:

- `run` writes a one-line wrapper per declared host tool into a temp dir and
  binds it into the box at `/run/shellbox-host-bin` (prepended to `PATH`).
- Each wrapper execs `systemd-run --user --wait --pipe --working-directory="$PWD"
  -- <tool> "$@"`. Your user systemd manager (reached through the bound
  `$XDG_RUNTIME_DIR` socket, authenticated by uid) runs the tool **on the host**
  — host rootfs, host binaries — and streams stdio and the exit code back.

This is the same `systemd-run --user` model the project has always used, just
invoked directly from inside the box instead of through a parent bridge.
Requirements:

- The box image must contain `systemd-run` (container images don't ship it by
  default — add it in your Containerfile, e.g. `dnf install systemd` /
  `apt install systemd`). shellbox checks for it at `run` time and errors
  clearly if missing.
- A running `systemd --user` manager for your user (always present on a desktop
  login; on SSH/headless, `loginctl enable-linger <user>`).

`[host]` tools are a no-op in `shell` mode and via persistent exports, where the
real host tool is already on `PATH`.

### Extra bind mounts (`[[binds]]`)

A box can declare extra bind mounts to layer onto its runtime, applied **after**
shellbox's fixed binds (so a guest may overlay the rootfs). They use bwrap's
`-try` variants when `optional = true`, so an absent host path is skipped
silently — the same headless-safe contract as `$XDG_RUNTIME_DIR` and
`/tmp/.X11-unix`.

```toml
[[binds]]
host = "/sys"            # GPU/Vulkan render-node enumeration
guest = "/sys"
mode = "ro"
optional = true
```

`mode` is `ro` (default), `rw`, or `dev` (device nodes). Guests `/`, `/dev`, and
`/proc` are refused — they would shadow box-critical mounts. This is how a GUI
box (e.g. a terminal emulator) opts into the few display paths shellbox doesn't
already forward; shellbox already binds `$XDG_RUNTIME_DIR` (Wayland socket +
session D-Bus), `/tmp/.X11-unix` (X11), and `/dev` (DRI/GPU) by default.

**Caveat: the guest path must already exist in the (read-only) box rootfs.**
bwrap can't create it on the fly because the composefs root is read-only and the
guest's parent must be a writable layer. `/sys` works because every Linux
rootfs has it; a path like `/run/dbus` won't (Fedora's `/run` is read-only and
empty), so bind such paths only if the image creates them at build time. For
D-Bus specifically, prefer the session bus, which is already reachable at
`$XDG_RUNTIME_DIR/bus`.

---

## Commands

### `create`

Define a box by writing its manifest into `boxes/`.

```bash
shellbox create --name <name> --image <ref> [--tool <name>]... [--from <path>] [--force]
```

`--force` overwrites an existing box.

### `link`

Symlink an external authoring directory into `boxes/`, so edits land in the
source tree (e.g. a dotfiles repo). Unlike `create --from` (which copies),
`link` points at existing files.

```bash
shellbox link [<source>] [--name <name>] [--force]
```

`<source>` defaults to the current directory; the name defaults to the source
dir basename. The source is canonicalized to an absolute path before linking,
so relative paths won't dangle. `--force` overwrites an existing box.

### `prepare`

Materialize a box: build its image (if it ships a Containerfile), export the
rootfs, bake identity, and produce the composefs image. Then sync the box's
persistent tool exports so every declared `[shell].tools` wrapper is on your
`PATH` (and any tools it no longer declares are removed). Requires podman and
`mkcomposefs`.

```bash
shellbox prepare <name>
```

This is the single command to run after editing a box — its manifest or its
Containerfile. Exports follow a **last-prepare-wins** policy: if two boxes
declare the same tool, whichever was prepared most recently owns the export.
Removing that tool from the winner and re-preparing unexports it; re-prepare
the other box to reclaim it.

### `list`

List all known boxes with live status.

```bash
shellbox list
```

### `inspect`

Show a box's source, shell tools, state, paths, and last-prepared time.

```bash
shellbox inspect <name>
```

### `run`

Run one command inside the box runtime (rootfs-first). With no command, opens an
interactive shell (`/bin/bash` if present, else `/bin/sh`) inside the box
runtime — useful for inspecting/debugging the box itself. Exits with the
command's exit code.

```bash
shellbox run <name> -- <cmd> [args...]
shellbox run <name>                 # interactive shell inside the box runtime
```

### `shell` (devshell mode)

Open a nested host shell with declared tools surfaced as wrappers on `PATH`.
Exit with `exit` or `Ctrl-D` to return to your previous shell.

```bash
shellbox shell <name>
```

Inside, declared tools resolve to wrappers that invoke `shellbox run`. You are
still "you" — same home, cwd, prompt, git config, SSH agent, etc.

### `rm`

Remove a box's derived artifacts. The manifest is kept by default.

```bash
shellbox rm <name>                 # remove derived artifacts; keep manifest
shellbox rm <name> --purge         # also remove the manifest directory
shellbox rm <name> --purge --force # required to purge a symlinked box
```

`--purge` on a symlinked box requires `--force` (the symlink is removed; the
target is left untouched). Any exports owned by the box are removed
automatically.

### `list-exports`

List all exported tools and the box that owns each. Exports themselves are
synced by `prepare` (and cleaned up by `rm`); this command is read-only.

```bash
shellbox list-exports
```

---

## Examples

### Image-backed box

```bash
shellbox create --name fedora-rg --image localhost/local/fedora-rg:latest --tool rg
shellbox prepare fedora-rg

shellbox run fedora-rg -- rg --version
shellbox run fedora-rg                 # interactive shell inside box runtime
shellbox shell fedora-rg               # nested host shell with rg on PATH
```

### Export tools for use across shells

```bash
shellbox prepare fedora-rg          # builds image, materializes, and syncs exports
export PATH="$HOME/.local/share/shellbox/exports/bin:$PATH"
rg --version
```

Add the `PATH` entry to your shell rc once; afterwards, editing the manifest or
Containerfile and re-running `prepare` keeps the exports in sync.

### Building from a Containerfile

```bash
# boxes/mybox/Containerfile
FROM registry.fedoraproject.org/fedora:44
RUN dnf -y install ripgrep fd-find && dnf clean all

# boxes/mybox/shellbox.toml
#   image = "localhost/mybox:latest"
#   [shell]
#   tools = ["rg", "fd"]
shellbox create --name mybox --from ./boxes/mybox
shellbox prepare mybox              # builds the Containerfile into the image, then materializes
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
authored manifest (and any companion files like bundled config). Because derived
artifacts live under `~/.local/state/shellbox/<name>/` — **not** in the box
directory — nothing machine-specific is written into your repo.

`rm` without `--purge` is always safe (it never touches the symlink or its
target); `rm --purge` on a symlinked box requires `--force` and removes only the
symlink.

---

## Storage layout

```text
~/.local/share/shellbox/
  boxes/<name>/             # authored files only (may be a symlink)
    shellbox.toml           # manifest — single source of truth
  store/                    # shared composefs digest store
  exports/
    bin/<tool>              # persistent tool wrappers (add to PATH)
    metadata/<tool>.json    # export ownership records

~/.local/state/shellbox/
  <name>/                   # all per-box derived state
    metadata.json           # prepare hint (not authoritative)
    image.cfs               # composefs image
    rootfs/                 # exported rootfs (prepare input)
  sessions/                 # ephemeral devshell wrapper dirs
```

---

## How identity works

When you run a box, tools like `whoami` and your shell prompt need to resolve
your username. shellbox solves this by **baking your user identity into the
rootfs at prepare time**: during `prepare`, your passwd/group entries are merged
into the rootfs's `/etc` (while it is still a normal writable directory), before
`mkcomposefs` freezes it into a read-only image.

Consequences:

- `whoami`, `id`, and prompt username all work inside `run`
- zero runtime overhead — no temp dirs or overlays per invocation
- any image works
- identity is per-user, matching the per-user storage model

Because identity is baked at prepare time, you must **re-prepare** after
changing the user account (e.g. new uid/gid) for it to take effect.

### Desktop integration

The box runtime is **not** a hermetic desktop sandbox. By default `run`
bind-mount your user runtime directory (`$XDG_RUNTIME_DIR`) and the X11
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

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

Boxes are **immutable**. To change one, edit its manifest and re-prepare.

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

A box has three states:

1. **defined** — manifest exists, nothing prepared yet
2. **prepared** — composefs artifacts exist, can be used (run/shell mount it rootlessly on demand)
3. **mounted** — (optional) kernel composefs mount exists; run/shell use it as a fast path

Transitions are explicit and predictable:

```
create  -> defined
prepare -> prepared
mount   -> mounted
unmount -> prepared
rm      -> removed
```

`run` and `shell` do **not** auto-prepare. They do auto-mount
(rootlessly, via FUSE) if the box is not already kernel-mounted.

### Two workflows

shellbox supports two clearly distinct workflows:

**Devshell workflow** — host-shell first, tools surfaced into your shell:

- `shell` — open a nested shell with box tools added to `PATH`
- `export` — persistently install a box tool wrapper

**Runtime workflow** — box rootfs first, for debugging/strict execution:

- `run` — run one command inside the box runtime, or open an interactive shell
  when no command is given

`run` is the runtime primitive; `shell` and `export` are thin tool
surfacing features built on top of `run`.

### Privilege model

**Nothing requires `sudo` for normal use.** `run` and `shell`
mount the composefs image via a fully rootless FUSE runtime (a private user +
mount namespace, with a background FUSE server thread) when the box is not
already mounted. No persistent host mount is created; the FUSE mount lives only
for the duration of the command.

`mount` and `unmount` (which create a persistent, host-visible **kernel**
composefs mount) still require `sudo` and are now **optional** — useful for
heavy, repeated use where you want the kernel driver's speed and a shared
mount across invocations. When a box is kernel-mounted, `run`/`shell`
automatically use that fast path instead of FUSE.

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
```

### Precedence

CLI flags override or append on top of an imported manifest:

- `--name` / `--image` **override** manifest values
- `--tool` **appends** to the manifest's tools
- an `image` is required (from the manifest, `--image`, or `--from`)

### Environment variables

You can declare env vars to set whenever the box is used (`run`, `shell`,
or via `export`). Values are **plain strings** — there is no token
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

How it works (no daemon, no extra host packages beyond systemd):

- `run` starts a private, session-scoped Unix socket **in the parent
  `shellbox` process**, then bind a tiny static helper (`shellbox-host-exec`,
  installed alongside `shellbox`) and a one-line wrapper per host tool into the
  bwrap at `/run/shellbox-host-bin` (prepended to `PATH`).
- The wrapper execs the helper, which streams the command over the socket; the
  parent runs it on the host via `systemd-run --user --wait --pipe` and streams
  stdio and the exit code back.

The socket and any in-flight host commands **live and die with the box
session** — nothing outlives `run`. Requirements: a running
`systemd --user` manager for your user (always present on a desktop login; on
SSH/headless, `loginctl enable-linger <user>`). `[host]` tools are a no-op in
`shell`/`export` modes, where the real host tool is already on `PATH`.

For cross-distro portability, build `shellbox-host-exec` statically (e.g.
`cargo build --release -p shellbox-host-exec --target x86_64-unknown-linux-musl`)
so it links no host glibc.

---

## Commands

### `create`

Define a box by writing its manifest into `boxes/`.

```bash
shellbox create --name <name> --image <ref> [--tool <name>]... [--from <path>] [--force]
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

### `prepare`

Materialize composefs artifacts from the box's image. Requires podman and
`mkcomposefs`.

```bash
shellbox prepare <name>
```

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

### `mount` / `unmount`

**Optional.** Create or remove a persistent, host-visible **kernel** composefs
mount. Require `sudo`. When present, `run`/`shell` use this kernel
mount as a fast path; otherwise they fall back to the rootless FUSE runtime.

```bash
sudo shellbox mount <name>
sudo shellbox unmount <name>
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

Refuses if mounted. `--purge` on a symlinked box requires `--force` (the symlink
is removed; the target is left untouched). Note any exports that still
reference the box so you can clean them up.

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
shellbox prepare fedora-rg
# optional: sudo shellbox mount fedora-rg   (kernel fast path; skip to use rootless FUSE)

shellbox run fedora-rg -- rg --version
shellbox run fedora-rg                 # interactive shell inside box runtime
shellbox shell fedora-rg               # nested host shell with rg on PATH

# sudo shellbox unmount fedora-rg   (only if you mounted above)
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
    metadata.json           # prepare/mount cache (not authoritative)
    image.cfs               # composefs image
    rootfs/                 # exported rootfs (prepare input)
    mount/                  # composefs mountpoint
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

# AGENTS.md

Reference for agents (human or automated) working in this codebase. This is the
source of truth for architecture, design decisions, data models, and where
things live. The `README.md` is the human-facing usage doc; this is the
implementation reference.

---

## What shellbox is

A Rust CLI that builds named dev environments ("boxes") from OCI images or
Containerfiles into composefs-backed read-only root filesystems, and runs them
rootlessly with `bwrap`. It supports two workflows:

- **devshell** (`shell`, `export`): surface box tools into the host shell
- **runtime** (`run`, `enter`): execute inside the box rootfs

`run` and `enter` are runtime primitives; `shell` and `export` are thin
surfacing layers over `run`.

---

## Source layout

Currently a flat module structure under `src/`:

```
src/
  main.rs        # clap parse + dispatch to app::cmd_*
  cli.rs         # clap structs/enums (Command, CreateArgs, RunArgs, ExportArgs, ...)
  app.rs         # all command handlers + helpers (build, mount, runtime, identity, exports, migrate)
  paths.rs       # XDG path resolution (respects SUDO_UID under sudo)
  config.rs      # BoxManifest (TOML, source of truth) + ShellConfig + name/tool validation
  metadata.rs    # BoxMetadata (JSON cache/hint)
  util.rs        # subprocess helpers (run_command, command_output, run_command_inherit)
```

There is no `commands/` or `build/` module split yet; `app.rs` holds everything.
A future refactor could split it, but keep behavior identical.

---

## Build & run

```bash
cd /work/bw/shellbox
./build.sh        # podman-based build -> target-host/shellbox
cargo build       # if local cargo is available
```

To install an updated binary into place during iteration:

```bash
cp target/debug/shellbox target-host/shellbox.new && \
  chmod +x target-host/shellbox.new && \
  mv -f target-host/shellbox.new target-host/shellbox
```

(The `cp` may hit "Text file busy" if the binary is running; the `.new`+`mv`
dance avoids it.)

---

## Crates

From `Cargo.toml`:

- `clap` (derive) — CLI parsing
- `serde` + `serde_json` — `metadata.json`, export records, legacy migration
- `toml` — authoring format (`shellbox.toml`), read and written in place
- `anyhow` — error handling (all handlers return `anyhow::Result<()>`)
- `nix` (feature `user`) — uid/gid, `User`, `Group` lookups
- `owo-colors` — terminal styling
- `humantime` — human-readable timestamps in `inspect`
- `tempfile` — ephemeral dirs for devshell sessions

### External tools (shelled out)

- `podman` — create/export containers, build from Containerfile
- `mkcomposefs` — generate composefs images
- `mount` / `umount` — composefs mount lifecycle (privileged)
- `mountpoint` — live mount state checks
- `bwrap` — rootless runtime execution
- `bash -lc` — permission normalization and `cp -a` for rootfs/migration handling
- `cp -a` — vendoring directories/files into `boxes/` and migration moves

Design rule: **policy in Rust, system work delegated to proven host tools.**

---

## The vendored-box model (important)

Each box is **vendored** under `~/.local/share/shellbox/boxes/<name>/`, and the
`shellbox.toml` inside it is the **single source of truth**. There is no
separate stored config (`config.json` was removed in this design pass). Every
command that needs box definition reads the manifest in place.

Consequences that show up throughout the code:

- **The box name *is* the directory name.** Identity is the directory. Renaming
  is a first-class operation (`rename`) that moves the manifest dir, the state
  dir, and rewrites exports.
- **No absolute self-referential paths are stored.** Source is `image` in the
  manifest or a co-located `Containerfile`. There is no `{manifest_dir}` token;
  env values are plain strings.
- **Authored files and derived artifacts are split across two roots** so that
  symlinked boxes (dotfiles) don't drag machine-specific state into version
  control, and `rm` can drop artifacts without destroying the manifest.
- **`migrate`** converts legacy `config.json` boxes to this layout (freezing
  `{manifest_dir}` tokens to literals).

When extending anything that touches box identity or location, preserve these
invariants.

---

## Commands & behavior

Command dispatch lives in `main.rs`; handlers are `app::cmd_*`.

### `create`
- Args: `--name`, `--image`|`--file`, repeatable `--tool`, `--from`, `--force`
- `--from` imports from an external file or directory (auto-discovers
  `./shellbox.toml` if omitted). For `--from <dir>`, the whole directory is
  copied into `boxes/<name>/`; for `--from <file>`, only that manifest.
- Precedence: CLI `--name`/`--image`/`--file` **override** the import;
  `--tool` **appends**; exactly one source required total. `image` wins over a
  stray co-located Containerfile.
- name resolution: `--name` > manifest `name` field > `--from` dir name
- Validates name (`[A-Za-z0-9_-]`) and tool names (no whitespace/`/`/NUL)
- Writes `boxes/<name>/shellbox.toml` (always sets `name = <dir name>`), vendors
  the Containerfile if containerfile-backed (or removes a stray one if
  image-backed), and creates an empty `state/<name>/metadata.json`
- `--force` overwrites an existing box (refuses if mounted)

### `link`
- Args: optional positional `source`, `--name`, `--force`
- Symlinks an external authoring dir into `boxes/<name>/` (no copy, unlike
  `create --from`). Source defaults to the current directory; name defaults to
  the source dir basename.
- Canonicalizes the source to an absolute path before linking (so relative
  sources don't dangle under `boxes/`).
- Creates an empty `state/<name>/metadata.json` so the linked box is usable.
- `--force` overwrites an existing box (refuses if mounted).

### `rename`
- Args: `<old>`, `<new>`
- Validates `<new>`; refuses if `<old>` doesn't exist, `<new>` exists, or
  `<old>` is mounted
- `mv boxes/<old> boxes/<new>` (renames the symlink itself if symlinked) and
  `mv state/<old> state/<new>`
- Updates the manifest `name` field if it differs from `<new>`
- Regenerates every export wrapper owned by the box (rewriting the
  `shellbox run <name>` line) and rewrites export metadata `box_name`

### `build`
- Fails if mounted (must unmount first)
- Clears/recreates `state/<name>/rootfs/`
- Source: `image` from manifest, or `build_containerfile` using
  `boxes/<name>/Containerfile` with **context = `boxes/<name>/`** →
  `localhost/shellbox-build-<name>:latest`
- `podman create <image>` → capture cid → `podman export <cid> | tar ...` into
  `rootfs/` → `podman rm <cid>` (always, even on failure)
- `normalize_rootfs_permissions`: `chmod u+r`/`u+rx` on unreadable files so
  rootless hashing works
- `inject_runtime_identity` (see Identity below)
- `inject_name_resolution` (copies host `/etc/resolv.conf` + `/etc/hosts` as
  mount-point placeholders for the live runtime ro-binds)
- `inject_desktop_mount_points` (pre-creates `/run/user/<uid>`)
- `mkcomposefs --skip-devices --user-xattrs --digest-store=<store> <rootfs> <state>/<name>/image.cfs`
- Sets `built=true`, `mounted=false`, `last_built_at` in `state/<name>/metadata.json`

### `mount` / `unmount`
- Require `geteuid()==0` (fail with clear message otherwise)
- Mountpoint is `state/<name>/mount`
- `mount` chowns the mountpoint dir to `SUDO_UID:SUDO_GID` before mounting
- Mount: `mount -t composefs -o basedir=<store> <image.cfs> <mountpoint>`
- Both are idempotent (no-op if already in the target state)
- Live state is checked via `mountpoint -q`, not trusted from metadata

### `run` / `enter`
- Require built + mounted (live check via `mountpoint`)
- Load `BoxManifest` and apply `manifest.shell_env()` (**verbatim**, no
  expansion) via bwrap `--setenv` *after* the HOME/USER/LOGNAME/PATH defaults,
  so declared env overrides them
- `enter` runs an interactive shell; picks `/bin/bash` if present else `/bin/sh`
- `run` runs the given command (uses clap `last = true` capture so `--` works)
- Both use `run_in_box`: a plain bwrap invocation (see Runtime below)
- Exit with the child's exit code (`process::exit(code)`)

### `shell` (devshell mode)
- Requires box has shell tools configured
- Creates an ephemeral `TempDir` under `sessions/` with a `bin/` of wrappers
- Each wrapper inlines the box env (verbatim) as `export VAR=...` lines, then
  `exec <shellbox> run <box> -- <tool> "$@"`
- Spawns `$SHELL` (default `/bin/sh`) with `PATH` prepended, `SHELLBOX_NAME`,
  `SHELLBOX_EXPORT_MODE=ephemeral`, `SHELLBOX_WRAPPER_DIR`, and the box env vars
- `TempDir` is dropped after the child exits → auto-cleanup
- `exit`/`Ctrl-D` returns to the parent shell naturally (child process model)

### `export`
- Args: `<name>`, optional `<cmd>`, `--all`, `--force`
- Requires exactly one of `<cmd>` or `--all`
- Loads `BoxManifest`; the wrapper inlines `manifest.shell_env()` (verbatim) as
  `export VAR=...` lines so persistent exports work outside any session
- Writes wrapper to `exports/bin/<tool>` + metadata to `exports/metadata/<tool>.json`
- Collision: if `<tool>.json` exists and is owned by a different box, fail
  unless `--force`; if bin target exists and no metadata, fail unless `--force`

### `unexport`
- Args: optional `<tool>`, `--all`, `--box <name>` (only valid with `--all`)
- Exactly one of `<tool>` or `--all` required (else error)
- `<tool>` + `--all` is an error
- `--all` scopes to `--box <name>` if given (filters by `ExportRecord.box_name`)
- Idempotent: removing a nonexistent export succeeds and reports "no metadata"
- `remove_export` deletes both wrapper (`exports/bin/<tool>`) and metadata
  (`exports/metadata/<tool>.json`), returning the prior owner if metadata existed

### `list-exports`
- Scans `exports/metadata/*.json`, deriving tool name from filename stem
- Sorted by tool, then box name
- Skips unreadable metadata with a warning rather than aborting
- Prints `tool (box)`, target path, and box name

### `rm`
- Refuses if mounted (live check) or metadata says mounted
- **Default (no `--purge`)**: removes only `state/<name>/` (derived artifacts);
  keeps `boxes/<name>/` (the manifest). This is safe because the manifest is
  the only copy of authoring.
- `--purge`: also removes `boxes/<name>/`. If the box dir is a symlink, requires
  `--force`; only the symlink is removed (the target is untouched).
- `chmod -R u+rwX` + `rm -rf --one-file-system` for stubborn perms
- Prints a note counting any exports still referencing the box

### `list` / `inspect`
- `list` scans `boxes/*/shellbox.toml` (follows symlinks); skips unreadable
  manifests with a warning
- Both compute live status (defined/built/mounted) and show recorded-vs-live
  with a "drift" indicator when they disagree
- `inspect` also prints shell tools and env (verbatim)

### `migrate`
- One-time conversion of legacy `config.json` boxes to the vendored layout
- For each `boxes/<name>/` that has `config.json` but no `shellbox.toml`:
  - Refuses if still mounted (legacy mountpoint was `state/mounts/<name>`)
  - Parses legacy `config.json` (tagged `source` enum, `shell`, `manifest_dir`)
    and legacy `metadata.json`
  - Writes `shellbox.toml` (image from `image_ref` source; containerfile source
    → vendors the referenced file as `Containerfile`)
  - **Freezes `{manifest_dir}` tokens** in env values to literal absolute paths
    using the recorded `manifest_dir`; warns if a token is present but no
    `manifest_dir` was recorded (leaves the literal token in place)
  - Moves `image.cfs`/`rootfs/` from `boxes/<name>/` and the legacy mountpoint
    (`state/mounts/<name>`) into `state/<name>/` (cfs, rootfs, mount)
  - Writes new `metadata.json` (`built`, `mounted: false`, `last_built_at`)
  - Removes old `config.json` and `metadata.json`
- Idempotent: boxes already in the new layout are skipped

---

## Data models

### `shellbox.toml` (`BoxManifest`, serde TOML) — source of truth, read in place

```toml
name = "fedora-rg"            # optional; must match the box dir if present
image = "localhost/local/...:latest"   # OR omit and co-locate a Containerfile
[shell]
tools = ["rg", "fd"]
[shell.env]
FOO = "bar"                   # plain string, no expansion
```

- Parsed by `BoxManifest::load_from` whenever a command needs it; also written
  by `create`/`rename` via `BoxManifest::save` (TOML, pretty-printed).
- `shell.tools` defaults to `[]`; `shell.env` defaults to `{}`.
- There is **no** `file` field (legacy field is silently ignored on parse) and
  **no** `{manifest_dir}` expansion. Env values are applied verbatim everywhere.
- `shell_env()` returns the env as a sorted `(String, String)` vec, verbatim.

### `metadata.json` (`BoxMetadata`, serde JSON) — cache/hint only

```json
{
  "built": true,
  "mounted": false,
  "last_built_at": "1700000000"
}
```

Paths are **not** stored here — they are always derivable from the box name via
`Paths::box_paths`. `metadata.json` is a cache/hint, not authoritative:
commands re-check live state (`cfs_path.exists()`, `mountpoint -q`). Missing
metadata is treated as default (all false) by callers (`unwrap_or_default()`).
`last_built_at` is a unix-seconds string.

### Legacy structs (used only by `migrate`)

`LegacyConfig`, `LegacySource` (`ImageRef`/`ContainerfilePath` tagged enum),
`LegacyShell`, `LegacyMetadata` — serde structs matching the pre-vendoring
on-disk JSON, defined in `app.rs` and used only by `cmd_migrate`/`migrate_one`.

---

## Storage layout (paths.rs)

Resolved from the real user's home; under `sudo` it uses `SUDO_UID` to find the
invoking user's home via `nix::unistd::User::from_uid`.

```
~/.local/share/shellbox/
  boxes/<name>/                  # authored files only (may be a symlink)
    shellbox.toml
    Containerfile                # iff containerfile-backed
  store/                         # composefs digest store (shared across boxes)
  exports/
    bin/<tool>                   # add exports/bin to PATH
    metadata/<tool>.json         # { box_name, command }
~/.local/state/shellbox/
  <name>/                        # all per-box derived state
    metadata.json
    image.cfs
    rootfs/
    mount/                       # composefs mountpoint
  sessions/                      # ephemeral devshell TempDirs (shared)
```

`BoxPaths` (from `Paths::box_paths(name)`) bundles all of a box's paths:
`dir`, `manifest_path`, `containerfile_path`, `state_dir`, `metadata_path`,
`cfs_path`, `rootfs_path`, `mount_path`.

The split between `boxes/<name>/` (authored) and `state/<name>/` (derived) is
load-bearing: it is what makes symlinked boxes safe (no machine-specific writes
into the repo) and makes `rm` non-destructive of the manifest by default. Do
not co-locate derived artifacts back under `boxes/<name>/`.

---

## Runtime (bwrap) — `run_in_box`

Identity is baked at build time (see below), so runtime is intentionally
minimal. `run_in_box` builds:

```
bwrap \
  --bind <state>/<name>/mount / \
  --dev-bind /dev /dev \
  --proc /proc \
  --share-net \
  --ro-bind-try /etc/resolv.conf /etc/resolv.conf \
  --ro-bind-try /etc/hosts /etc/hosts \
  --tmpfs /tmp \
  --tmpfs /var \
  --dir /var/home \
  --bind $HOME $HOME \
  --chdir <cwd or $HOME> \
  --setenv HOME $HOME \
  --setenv USER <user> \
  --setenv LOGNAME <logname> \
  --setenv PATH /usr/bin:/usr/sbin \
  [--bind-try $XDG_RUNTIME_DIR $XDG_RUNTIME_DIR] \
  --ro-bind-try /tmp/.X11-unix /tmp/.X11-unix \
  <declared env vars as --setenv, verbatim> \
  <cmd...>
```

Why `/var` is a tmpfs: on Silverblue-like systems `$HOME` is under
`/var/home/...`; the composefs root is read-only, so bwrap needs writable
parents before binding the real home in. `cwd` falls back to `$HOME` if it
isn't under `$HOME` (e.g. a deleted directory).

The runtime does **not** mount `/etc` overlays or write identity files at run
time — that was tried and was fragile (read-only root fights every approach).
Identity lives in the rootfs itself.

`--share-net` keeps the host network namespace, matching the devshell model
("you, with extra tools"): git, plugin managers, LSP servers, etc. work as on
the host. Network isolation is not a goal of shellbox.

`/etc/resolv.conf` and `/etc/hosts` are `--ro-bind-try`'d from the host at
runtime. Container images don't ship a working resolv.conf (the container
runtime injects it), so without these DNS would fail even with `--share-net`.
They must also be *baked* into the rootfs at build time (see
`inject_name_resolution`) because composefs is read-only and bwrap can't
create the mount-point files at runtime; the live ro-bind keeps them correct as
the host roams networks. `--ro-bind-try` (not `--ro-bind`) is used so a box
that predates this feature still boots if the files are absent.

### Box env vars (`shell.env`)

Declared env vars are applied **verbatim** (no token expansion) in all three
entry points so the box is declarative end-to-end:

- `run` / `enter`: passed to bwrap as `--setenv VAR VAL` *after* the
  HOME/USER/LOGNAME/PATH defaults, so declared vars override them. (bwrap does
  **not** `--clearenv`, so host env is otherwise inherited.)
- `shell`: set on the spawned host shell via `Command::env`.
- `export`: inlined into the wrapper script as `export VAR=...` lines, so
  persistent exports set the env before `shellbox run` (which then also
  re-applies them via bwrap — belt and suspenders).

Because values are plain literals, renaming a box does **not** rewrite env
values (only the `shellbox run <name>` line in regenerated wrappers). If a box
references paths that moved, the author updates the manifest.

---

## Identity — `inject_runtime_identity` (build time)

Called during `build`, after permission normalization, while `rootfs/` is still
a normal writable directory we own. It:

1. Ensures `rootfs/etc/` exists
2. Resolves current user via `nix::unistd::User::from_uid(Uid::current())`
   (fallback username from `$USER` or `user<uid>`; fallback gid from
   `Gid::current()`)
3. Gets all gids via `id -G` (deduped, primary gid ensured present)
4. `merge_passwd(rootfs/etc/passwd)`: drops any existing line for the same uid
   or username, then appends `<name>:x:<uid>:<gid>::<home>:<shell>`
5. `merge_group(rootfs/etc/group)`: for each user gid, finds the matching group
   row (by gid) and ensures the user is listed as a member; otherwise creates a
   new group row. Preserves existing groups.
6. `ensure_nsswitch_files(rootfs/etc/nsswitch.conf)`: if `passwd`/`group` lines
   don't already use `files`, writes a sane default preserving any existing
   `hosts:` line

`shell` field in passwd uses `default_enter_shell(root)`: `/bin/bash` if
`root/bin/bash` exists else `/bin/sh`.

Then `inject_name_resolution` copies the host's `/etc/resolv.conf` and
`/etc/hosts` into the rootfs, `inject_desktop_mount_points` pre-creates
`/run/user/<uid>`, and `mkcomposefs` freezes the edited `/etc` into the
read-only image.

### Implications for agents

- **Identity is baked per-build.** Changing the user account (uid/gid/username)
  requires `build` again. Do not try to fix identity at runtime.
- **Name resolution files are baked per-build too** (as mount-point
  placeholders), but the *values* are refreshed at runtime via `--ro-bind-try`
  from the host's live copies, so DNS stays correct without rebuilding when you
  roam networks. You only need to rebuild if the box predates this feature
  (missing files in rootfs → the ro-bind-try just skips them).
- Build runs **unprivileged**, as the invoking user — which is exactly the
  identity that will be used at runtime. This is by design.
- If a future feature needs host identity to differ from build identity, this
  model needs revisiting (e.g. bind-mount `/etc/passwd` at runtime, which we
  deliberately avoided).

---

## Privilege model

- Rootless: `create`, `build`, `list`, `inspect`, `run`, `shell`, `enter`,
  `rm`, `rename`, `export`, `migrate`
- Privileged (`sudo` required, enforced by `require_root`): `mount`, `unmount`

Under `sudo`, `paths.rs` resolves the *invoking* user's dirs via `SUDO_UID`,
not root's. Keep privileged code paths small and dumb — no privileged daemon.

---

## Error handling

- All handlers return `anyhow::Result<()>`
- Lower-level helpers attach context with `.context(...)`
- `util::run_command` captures stdout/stderr and surfaces them on failure
- `util::command_output` returns trimmed stdout on success
- `util::run_command_inherit` connects stdio for interactive commands (bwrap,
  shells)

When adding features, prefer clear actionable error messages, e.g.:

```
box 'rg' is not mounted
run: sudo shellbox mount rg
```

---

## Conventions & gotchas

- **Box name charset**: `[A-Za-z0-9_-]` only (validated in `config::validate_name`).
  This is also filesystem-safe everywhere, which matters because the name *is*
  the directory name.
- **Tool name charset**: no whitespace, no `/`, no NUL (`config::validate_tool_name`)
- **`--tool` is repeatable** and deduped via `normalize_tools`
- **Source exclusivity** is enforced both in clap (`conflicts_with` on
  `--image`/`--file`) and in `create`'s source resolution
- **Manifest `name` vs directory**: if a manifest's `name` field disagrees with
  its directory name, `require_manifest` prints a warning and proceeds using the
  directory name as authoritative. `rename` keeps them in sync.
- **Live state is truth**: never trust `metadata.json` alone for mount/built
  status — always `cfs_path.exists()` and `mountpoint -q`
- **`run`/`shell`/`enter` exit with the child's code** via `process::exit`, so
  any code after the handler in `main` won't run for those commands
- **Sessions cleanup**: `TempDir` must outlive the spawned shell; it's dropped
  after `run_command_inherit` returns
- **Styling**: `colors_enabled()` checks `is_terminal` + `NO_COLOR` + `TERM!=dumb`
- **Symlinked boxes**: `boxes/<name>` may be a symlink. Path construction uses
  the name-based path (so state lookups are consistent); file reads follow the
  symlink. `rename` renames the symlink entry; `rm --purge` on a symlink
  requires `--force` and removes only the symlink.

---

## Known limitations / future work

- No lock files for concurrent build/mount/rm/rename
- `rootfs/` is retained after build (no pruning/GC)
- No auto-mount on `run`/`shell` (intentional for latency/predictability)
- `shell` does not annotate the prompt yet (could add `SHELLBOX_NAME`-based
  prompt hooks later)
- No shell-native activation hook (`eval "$(shellbox shell-hook ...)"`) yet
- No custom bind mounts yet (manifest schema is designed to grow into `[[mount]]`;)
  this matters for things like display sockets for host clipboard integration
- `composefs`/`composefs-oci` Rust crates not used; we shell out to
  `mkcomposefs`/`mount` (intentionally, to reduce risk)

When extending the manifest, remember the schema is the source for
`BoxManifest` (TOML, read and written in place) — keep author-facing fields
minimal and explicit.

---

## Design stance (quick reference)

- **Explicit lifecycle**: no hidden auto-build/auto-mount
- **Immutable boxes**: change = edit source + rebuild
- **Vendored, single source of truth**: `boxes/<name>/shellbox.toml`, read in place
- **Name = directory**: identity is the directory; `rename` is first-class
- **Authored vs derived split**: `boxes/<name>/` vs `state/<name>/` (enables
  symlinked boxes and non-destructive `rm`)
- **Plain-string env**: no token expansion; authors hardcode paths
- **Minimal privileges**: only mount/unmount need root
- **Identity at build time**: not at runtime
- **Policy in Rust, mechanics in host tools**

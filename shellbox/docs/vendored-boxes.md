# PRD: Vendored boxes — single source of truth

Status: Draft / proposed
Scope: `shellbox`

## Problem

Today a box is defined in two places: an authored `shellbox.toml` (input-only)
and an internal `config.json` (storage, "source of truth"). `create` snapshots
the manifest into `config.json`, capturing absolute paths (`containerfile_path`,
`manifest_dir`). This causes:

- **Move brittleness**: moving the source tree orphans every box.
- **Two-model overhead**: `BoxManifest` vs `BoxConfig`, precedence rules, and
  prose explaining that editing the manifest after `create` does nothing.
- **Stale snapshots**: `config.json` can drift from the on-disk manifest.

## Goal

One source of truth per box, living at a known location, that never stores
absolute paths to itself. Support two workflows:

1. **nix-devshell style** — enter a named box to work on a project.
2. **bashrc base layer** — activate a named box from shell rc so it's always on.

Named boxes are retained because we manage persistent mounts keyed by name;
that constraint is not negotiable.

## Non-goals

- Path-addressed ("point at any toml anywhere") invocation, like nix flakes.
  Decided against: the mount-state requirement makes stable names necessary,
  and a single canonical location is simpler than dual modes.
- Auto-syncing external source trees. Authoring happens in `boxes/<name>/`
  (possibly via symlink); there is no background sync.

---

## Design

### Box location & layout

Every box is vendored under:

```
~/.local/share/shellbox/boxes/<name>/
  shellbox.toml       # the manifest — single source of truth
  Containerfile       # optional; presence => containerfile source
```

`boxes/<name>/` holds **authored files only**. It may be a symlink (see
Dotfiles below). Nothing derived is written here.

Derived artifacts move to the state directory, keyed by name:

```
~/.local/state/shellbox/<name>/
  image.cfs           # composefs image
  rootfs/             # exported rootfs (build input to mkcomposefs)
  mounts/             # (existing; composefs mountpoint — unchanged location)
  sessions/           # (existing; ephemeral devshell TempDirs)
```

> Rationale for splitting artifacts out of `boxes/<name>/`:
> 1. If `boxes/<name>/` is symlinked into a dotfiles repo, derived writes must
>    not land in the repo.
> 2. composefs artifacts are large, machine-specific, and rebuildable — they
>    belong in state, not in authoring/share.
> 3. It makes `rm` non-destructive by default (see below).
>
> This is a **decision to confirm**. The alternative (artifacts inside
> `boxes/<name>/artifacts/`) is simpler but breaks symlinked boxes and forces
> `rm` to be destructive.

### Single source of truth

`config.json` is **removed**. The manifest `shellbox.toml` is read in place by
every command that needs it. Implications:

- No `BoxConfig`/`BoxManifest` split; one struct, parsed on demand.
- No capture step, no drift, no "editing the manifest does nothing" caveat.

### Environment variables are plain strings

`shell.env` values are stored and applied **verbatim** — no token expansion of
any kind. The `{manifest_dir}` token is **removed**. If a box wants to point an
env var at an absolute path on disk, the author writes the absolute path.

Consequences:

- env values are static and self-describing; nothing is resolved at runtime.
- `rename` does not need to rewrite env values anywhere (they're literals).
- `export` wrappers inline the literal strings as-is.
- The nvim-style self-containment pattern (redirecting XDG dirs beside the
  manifest) is still possible — the author just hardcodes the absolute path to
  wherever they want that state to live. This is intentionally less "magic";
  it trades portability for simplicity and predictability. If a box is renamed
  or moved, the author updates the hardcoded paths in the manifest themselves.

### Source resolution

The manifest has either:

- `image = "<ref>"` → image source, or
- a co-located `Containerfile` → containerfile source.

No `file = "..."` field. The Containerfile must be named `Containerfile` and
live next to the manifest. Build context is always the box directory.

Exactly one source is required. `--image` / `--file` on the CLI override (see
create).

### Name ↔ directory coupling

The box name **is** the directory name under `boxes/`. Therefore:

- Name charset remains `[A-Za-z0-9_-]` (filesystem-safe everywhere).
- Renaming a box is a first-class operation (`rename`), not `mv`.
- The manifest's `name` field, if present, **must match** the directory name
  (validated on load; mismatch is a hard error with a clear message). This
  prevents the two from drifting silently.

---

## Commands

### `create` — define a box by writing its manifest into `boxes/`

`create` no longer snapshots external state; it *writes* the manifest into our
tree. Two modes:

**Flag mode** (scaffold from CLI):

```bash
shellbox create --name foo --image fedora:latest --tool rg --tool jq
shellbox create --name foo --file ./Containerfile --tool rg
```

- `--image` writes `shellbox.toml` with `image = "..."`.
- `--file <path>` **copies** the given file to `boxes/<name>/Containerfile`.
- Writes `boxes/<name>/shellbox.toml` from the resolved fields.
- Fails if `boxes/<name>/` already exists (use `--force` to overwrite, which
  refuses if mounted).

**Import mode** (`--from`):

```bash
shellbox create --name foo --from /path/to/dir
shellbox create --name foo --from /path/to/shellbox.toml
```

- If `<path>` is a directory: copy the whole dir (its `.toml` becomes the
  manifest; any `Containerfile` comes along). Requires the dir to contain
  exactly one manifest toml.
- If `<path>` is a file: copy it as `shellbox.toml` (image-based only, unless
  `--file` is also given to supply a Containerfile).
- CLI flags (`--name`, `--image`, `--tool`) **augment/override** the imported
  manifest, matching today's precedence: `--name`/`--image` override;
  `--tool` appends. `--name` is required (it names the target dir) unless
  derived from the source dir name in `--from` mode.

Precedence and validation rules otherwise unchanged from today.

### `rename` — rename a box and all derived state

```bash
shellbox rename <old> <new>
```

Atomically:

1. Validates `<new>` name charset and that `boxes/<new>/` doesn't exist.
2. Refuses if `<old>` is mounted.
3. `mv boxes/<old> boxes/<new>`.
4. `mv state/<old> state/<new>` (artifacts).
5. `mv mounts/<old> mounts/<new>` (if present).
6. Updates all `exports/metadata/*.json` whose `box_name == <old>` and rewrites
   the wrapper scripts' `shellbox run <new>` invocations.
7. If the manifest had a `name` field, update it to `<new>`.

Refuses to clobber. If symlinked, renames the symlink target name within
`boxes/` (not the real file's location) — see Dotfiles.

### `build` — unchanged behavior, new source lookup

Reads the Containerfile from `boxes/<name>/Containerfile` (containerfile source)
or uses `image`. Context = `boxes/<name>/`. Writes artifacts to
`state/<name>/`. Otherwise identical to today (permission normalization,
identity injection, name-resolution injection, mkcomposefs).

### `mount` / `unmount` — unchanged

Still require root, still keyed by name, still idempotent. Mountpoint stays at
`state/<name>/mounts/` (or wherever it is today; only the parent path changes).

### `run` / `enter` / `shell` — unchanged except manifest loading

Load the manifest from `boxes/<name>/shellbox.toml`. Apply `shell.env` values
verbatim (no expansion). Otherwise identical.

### `export` / `unexport` / `list-exports` — unchanged

`export` still inlines env values into the wrapper as literal `export VAR=...`
lines, so wrappers remain self-contained. `rename` must rewrite the wrapper's
`shellbox run <name>` invocation line; env values need no change since they
are author-supplied literals.

### `rm` — non-destructive by default

```bash
shellbox rm <name>            # remove derived artifacts + mount state; keep manifest
shellbox rm <name> --purge    # also remove boxes/<name>/ (the authored manifest)
```

- Default removes `state/<name>/` and `mounts/<name>/` but leaves
  `boxes/<name>/` (the manifest) intact. This is safe because the manifest is
  now the only copy of authoring.
- `--purge` also removes the manifest dir. Refuses if the dir is a symlink
  unless `--force` is also given (deleting through a symlink would delete the
  real dotfiles file — require explicit confirmation).
- Refuses if mounted, as today.

### `list` / `inspect` — read manifest in place

- `list` shows boxes by scanning `boxes/*/` for manifests.
- `inspect` prints source, tools, env, state, paths, last-built. Provenance is
  now trivially "the box directory."

---

## Dotfiles / version control via symlinks

A box can be a symlink:

```bash
ln -s ~/dotfiles/shellboxes/nvim ~/.local/share/shellbox/boxes/nvim
```

Supported use cases:

- Keep authored manifests (`shellbox.toml` + `Containerfile`) in a dotfiles
  repo, version-controlled and shareable.
- Because derived artifacts live in `state/<name>/` (not in the symlinked dir),
  nothing machine-specific is written into the repo. This is the key reason
  artifacts are split out.

Rules for symlinked boxes:

- All path resolution uses the *name* (`boxes/<name>`) for state lookups, and
  follows the symlink for reading authored files.
- `rename` on a symlinked box renames the symlink entry in `boxes/`, not the
  real file.
- `rm` without `--purge` is always safe (doesn't touch the symlink or its
  target).

---

## Migration

Existing boxes use `config.json` + absolute paths. Provide a one-time
migration:

```bash
shellbox migrate    # or run automatically on first use of the new binary
```

For each existing `boxes/<name>/config.json`:

1. Read the old `config.json`.
2. Materialize `shellbox.toml` from it:
   - `image` from `source.kind == image_ref`, or
   - containerfile source: copy the referenced `containerfile_path` file into
     `boxes/<name>/Containerfile` (best-effort; warn if missing).
3. Write `shell.env` **with any `{manifest_dir}` tokens resolved to their
   literal absolute values** as captured in the old `manifest_dir` field.
   Since expansion is gone in the new model, migrated env values must be frozen
   to plain strings. If `manifest_dir` was `None`, the literal `{manifest_dir}`
   text is preserved as-is (it will no longer expand; log a warning so the
   author can fix it).
4. Move `image.cfs` and `rootfs/` from `boxes/<name>/` to `state/<name>/`.
5. Delete `config.json` and `metadata.json` (or archive them).
6. Report any boxes whose source files were missing/unresolvable and mark them
   for manual fixup.

Migration is idempotent: a box already in the new layout is skipped.

---

## Open questions

1. **Manifest filename**: keep `shellbox.toml` (familiar, matches today) or
   rename to `box.toml` (shorter, reads cleaner now that it's always at a known
   path)? Recommendation: keep `shellbox.toml` to minimize churn.
2. **Artifacts location**: confirm `state/<name>/` split (recommended) vs
   `boxes/<name>/artifacts/`. The split is required for clean symlink support;
   the downside is a slightly less obvious layout.
3. **`create --from` when source already has a `name` field**: trust it, or
   always require `--name`? Recommendation: trust the field if present, else
   require `--name`; always validate it matches the target dir name.
4. **Auto-discovery of `./shellbox.toml`** (today `create` auto-discovers in
   cwd): keep for `--from .` ergonomics, or drop since boxes now live under
   `boxes/`? Recommendation: keep auto-discovery only as the default for
   `--from` when `--from` is omitted, to ease the dotfiles-import flow.

---

## Summary of what changes

| Area | Before | After |
|---|---|---|
| Source of truth | `config.json` (snapshot) | `shellbox.toml` in place |
| Box location | `boxes/<name>/` (mixed) | `boxes/<name>/` (authored only, maybe symlink) |
| Artifacts | `boxes/<name>/` | `state/<name>/` |
| Absolute paths stored | yes (`containerfile_path`, `manifest_dir`) | none |
| Containerfile source | `file = "..."` or `--file` (any path) | co-located `Containerfile` |
| `create` | snapshot external state | write manifest into `boxes/` |
| `rename` | not supported | first-class, syncs all state |
| `rm` | nukes everything | non-destructive; `--purge` for manifest |
| Dotfiles/VCS | via copy (`--from`) | copy or symlink |
| Env var values | `{manifest_dir}` token expanded at runtime | plain literal strings, no expansion |

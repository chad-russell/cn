use crate::cli::{CreateArgs, ExportArgs, LinkArgs, NameArgs, RenameArgs, RmArgs, RunArgs, UnexportArgs};
use crate::config::{self, BoxManifest, ShellConfig};
use crate::metadata::BoxMetadata;
use crate::paths::Paths;
use crate::util::{command_output, run_command, run_command_inherit};
use anyhow::{Context, Result, bail};
use nix::unistd::{Gid, Group, Uid, User};
use owo_colors::OwoColorize;
use serde::{Deserialize, Serialize};
use std::ffi::OsString;
use std::io::IsTerminal;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tempfile::{Builder, TempDir};

// ===========================================================================
// Source resolution
// ===========================================================================

/// The resolved source of a box, used by `build`.
enum Source {
    Image(String),
    Containerfile,
}

/// Determine a box's source from its manifest and on-disk layout.
///
/// `image` in the manifest wins if present. Otherwise a co-located
/// `Containerfile` is required. A stray `Containerfile` next to an image-backed
/// box is ignored.
fn resolve_source(manifest: &BoxManifest, box_paths: &crate::paths::BoxPaths) -> Result<Source> {
    if let Some(image) = &manifest.image {
        return Ok(Source::Image(image.clone()));
    }
    if box_paths.containerfile_path.exists() {
        return Ok(Source::Containerfile);
    }
    bail!(
        "box '{}' has no source\nset 'image' in the manifest or add a Containerfile beside it",
        box_paths.dir.display()
    );
}

/// Load the manifest for a box, with a clear error if the box isn't defined.
fn require_manifest(box_paths: &crate::paths::BoxPaths) -> Result<BoxManifest> {
    let manifest = BoxManifest::load_from(&box_paths.manifest_path)?;
    // The directory name is the source of identity. If the manifest declares a
    // `name` that disagrees, warn (but don't fail) so a hand-edit can't lock
    // the box out of every command.
    if let Some(declared) = &manifest.name {
        let dir_name = box_paths
            .dir
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("");
        if declared != dir_name {
            eprintln!(
                "warning: manifest 'name' is '{}' but the box directory is '{}'; the directory name is authoritative",
                declared, dir_name
            );
        }
    }
    Ok(manifest)
}

// ===========================================================================
// create
// ===========================================================================

struct Import {
    manifest: Option<BoxManifest>,
    /// Path to a Containerfile found in the import source.
    containerfile: Option<PathBuf>,
    /// Directory whose contents should be copied wholesale into the box dir.
    /// Only set for an explicit `--from <dir>`.
    extras_dir: Option<PathBuf>,
}

pub fn cmd_create(args: CreateArgs) -> Result<()> {
    let paths = Paths::new()?;
    paths.ensure_base_dirs()?;

    // Resolve the import source.
    let import = match &args.from {
        Some(p) => import_from_explicit(Path::new(p))?,
        None => import_from_cwd_auto()?,
    };

    // name: CLI > manifest 'name' > --from dir name.
    let name = args
        .name
        .clone()
        .or_else(|| import.manifest.as_ref().and_then(|m| m.name.clone()))
        .or_else(|| {
            if let Some(p) = &args.from {
                let pb = PathBuf::from(p);
                if pb.is_dir() {
                    return pb.file_name().and_then(|n| n.to_str()).map(String::from);
                }
            }
            None
        })
        .context(
            "box name is required\nprovide --name, a 'name' field in the manifest, or name the --from directory",
        )?;
    config::validate_name(&name)?;

    let box_paths = paths.box_paths(&name);

    // source: CLI --image/--file override the import; image wins over file.
    let final_image = args
        .image
        .clone()
        .or_else(|| import.manifest.as_ref().and_then(|m| m.image.clone()));
    let final_containerfile = args
        .file
        .as_ref()
        .map(PathBuf::from)
        .or_else(|| import.containerfile.clone());
    // `image_source` is Some for an image-backed box; None means containerfile-backed.
    let image_source: Option<String> = match (final_image, final_containerfile.clone()) {
        (Some(image), _) => Some(image),
        (None, Some(p)) => {
            if !p.exists() {
                bail!("containerfile does not exist: {}", p.display());
            }
            None
        }
        (None, None) => bail!(
            "exactly one source is required\nprovide --image or --file, set 'image' in the manifest, or place a Containerfile beside the manifest"
        ),
    };

    // tools: CLI appends to manifest.
    let mut tools = import
        .manifest
        .as_ref()
        .map(|m| m.shell.tools.clone())
        .unwrap_or_default();
    tools.extend(args.tools);
    let tools = normalize_tools(tools)?;

    let env = import
        .manifest
        .as_ref()
        .map(|m| m.shell.env.clone())
        .unwrap_or_default();

    // Materialize the box directory.
    if box_paths.dir.exists() {
        if !args.force {
            bail!("box '{}' already exists; use --force to overwrite", name);
        }
        if is_mountpoint(&box_paths.mount_path) {
            bail!("box '{}' is mounted; unmount it before overwriting", name);
        }
        remove_tree_force(&box_paths.dir)?;
    }
    std::fs::create_dir_all(&box_paths.dir)
        .with_context(|| format!("failed to create {}", box_paths.dir.display()))?;

    // Copy companion files from an explicit --from <dir>.
    if let Some(extras) = &import.extras_dir {
        copy_dir_contents(extras, &box_paths.dir)?;
    }

    // Write the canonical manifest.
    let manifest = BoxManifest {
        name: Some(name.clone()),
        image: image_source.clone(),
        shell: ShellConfig { tools, env },
    };
    manifest.save(&box_paths.manifest_path)?;

    // Place (or remove) the Containerfile to match the resolved source.
    match &image_source {
        None => {
            // containerfile source: vendor the file in.
            let src = final_containerfile.expect("containerfile path");
            std::fs::copy(&src, &box_paths.containerfile_path).with_context(|| {
                format!(
                    "failed to copy {} to {}",
                    src.display(),
                    box_paths.containerfile_path.display()
                )
            })?;
        }
        Some(_) => {
            // image source: avoid an ambiguous on-disk state if the import dragged one in.
            if box_paths.containerfile_path.exists() {
                let _ = std::fs::remove_file(&box_paths.containerfile_path);
            }
        }
    }

    // Fresh derived-state metadata.
    std::fs::create_dir_all(&box_paths.state_dir)
        .with_context(|| format!("failed to create {}", box_paths.state_dir.display()))?;
    BoxMetadata::default().save(&box_paths.metadata_path)?;

    let colors = colors_enabled();
    println!("{} {}", style_action("created", colors), style_title(&name, colors));
    println!("  {:<12} {}", "manifest", box_paths.manifest_path.display());
    match &image_source {
        Some(image) => {
            println!("  {:<12} {}", "source", format!("image · {image}"));
        }
        None => {
            println!("  {:<12} {}", "source", format!("containerfile · {}", box_paths.containerfile_path.display()));
        }
    }
    println!("  {:<12} {}", "state", box_paths.state_dir.display());
    if !manifest.shell.tools.is_empty() {
        println!("  {:<12} {}", "tools", manifest.shell.tools.join(", "));
    }
    Ok(())
}

// ===========================================================================
// link
// ===========================================================================

/// Symlink an external authoring directory into `boxes/<name>/`.
///
/// Unlike `create --from <dir>` (which copies), `link` points the box at
/// existing authoring so edits land in the source tree (e.g. a dotfiles repo).
/// See `docs/vendored-boxes.md` for the symlink workflow.
pub fn cmd_link(args: LinkArgs) -> Result<()> {
    let paths = Paths::new()?;
    paths.ensure_base_dirs()?;

    // Resolve the source directory (default: current directory).
    let source = match &args.source {
        Some(p) => PathBuf::from(p),
        None => std::env::current_dir().context("failed to get current directory")?,
    };
    if !source.is_dir() {
        bail!("source is not a directory: {}", source.display());
    }

    // Canonicalize to an absolute path. This is the whole reason `link`
    // exists over a manual `ln -s`: a relative source would dangle once it's
    // interpreted relative to `boxes/`, so we resolve it here.
    let canonical = source.canonicalize().with_context(|| {
        format!("failed to canonicalize source path {}", source.display())
    })?;

    // name: CLI > source dir basename.
    let name = args
        .name
        .clone()
        .or_else(|| canonical.file_name().and_then(|n| n.to_str()).map(String::from))
        .context("box name is required\nprovide --name or run from inside the source directory")?;
    config::validate_name(&name)?;

    let box_paths = paths.box_paths(&name);

    // Handle an existing entry under boxes/<name>.
    if box_paths.dir.exists() {
        if !args.force {
            bail!(
                "box '{}' already exists; use --force to replace it",
                name
            );
        }
        if is_mountpoint(&box_paths.mount_path) {
            bail!("box '{}' is mounted; unmount it before replacing", name);
        }
        remove_tree_force(&box_paths.dir)?;
    }

    // Create the symlink: boxes/<name> -> <canonical source>.
    std::os::unix::fs::symlink(&canonical, &box_paths.dir).with_context(|| {
        format!(
            "failed to symlink {} -> {}",
            box_paths.dir.display(),
            canonical.display()
        )
    })?;

    // Fresh derived-state metadata, so the linked box is immediately usable.
    std::fs::create_dir_all(&box_paths.state_dir)
        .with_context(|| format!("failed to create {}", box_paths.state_dir.display()))?;
    BoxMetadata::default().save(&box_paths.metadata_path)?;

    let colors = colors_enabled();
    println!("{} {}", style_action("linked", colors), style_title(&name, colors));
    println!("  {:<12} {}", "source", canonical.display());
    println!("  {:<12} {}", "box", box_paths.dir.display());
    println!("  {:<12} {}", "state", box_paths.state_dir.display());
    Ok(())
}

fn import_from_explicit(from_path: &Path) -> Result<Import> {
    if from_path.is_file() {
        let manifest = BoxManifest::load_from(from_path)?;
        return Ok(Import {
            manifest: Some(manifest),
            containerfile: None,
            extras_dir: None,
        });
    }
    if from_path.is_dir() {
        let manifest_path = from_path.join("shellbox.toml");
        let manifest = if manifest_path.is_file() {
            Some(BoxManifest::load_from(&manifest_path)?)
        } else {
            None
        };
        let containerfile = {
            let p = from_path.join("Containerfile");
            if p.is_file() {
                Some(p)
            } else {
                None
            }
        };
        Ok(Import {
            manifest,
            containerfile,
            extras_dir: Some(from_path.to_path_buf()),
        })
    } else {
        bail!("--from path does not exist: {}", from_path.display());
    }
}

/// Auto-discover `./shellbox.toml` (old behavior). No companion files.
fn import_from_cwd_auto() -> Result<Import> {
    let cwd = std::env::current_dir().context("failed to get current directory")?;
    let manifest_path = cwd.join("shellbox.toml");
    let manifest = if manifest_path.is_file() {
        Some(BoxManifest::load_from(&manifest_path)?)
    } else {
        None
    };
    Ok(Import {
        manifest,
        containerfile: None,
        extras_dir: None,
    })
}

fn copy_dir_contents(src: &Path, dst: &Path) -> Result<()> {
    // `cp -a src/. dst/` copies directory contents (including dotfiles) into dst.
    run_command(
        Command::new("cp")
            .arg("-a")
            .arg(format!("{}/.", src.display()))
            .arg(dst),
    )
}

// ===========================================================================
// build
// ===========================================================================

pub fn cmd_build(args: NameArgs) -> Result<()> {
    let paths = Paths::new()?;
    paths.ensure_base_dirs()?;
    let box_paths = paths.box_paths(&args.name);

    if !box_paths.manifest_path.exists() {
        bail!("box '{}' does not exist", args.name);
    }
    let manifest = require_manifest(&box_paths)?;
    let mut meta = BoxMetadata::load(&box_paths.metadata_path).unwrap_or_default();

    if is_mountpoint(&box_paths.mount_path) {
        bail!(
            "box '{}' is mounted at {}\nunmount it before rebuilding",
            args.name,
            box_paths.mount_path.display()
        );
    }

    if box_paths.rootfs_path.exists() {
        remove_tree_force(&box_paths.rootfs_path)?;
    }
    std::fs::create_dir_all(&box_paths.rootfs_path)
        .with_context(|| format!("failed to create {}", box_paths.rootfs_path.display()))?;

    let image_ref = match resolve_source(&manifest, &box_paths)? {
        Source::Image(image) => image,
        Source::Containerfile => build_containerfile(&args.name, &box_paths)?,
    };

    export_image_rootfs(&image_ref, &box_paths.rootfs_path)?;
    normalize_rootfs_permissions(&box_paths.rootfs_path)?;
    inject_runtime_identity(&box_paths.rootfs_path)?;
    inject_name_resolution(&box_paths.rootfs_path)?;
    inject_desktop_mount_points(&box_paths.rootfs_path)?;

    run_command(
        Command::new("mkcomposefs")
            .arg("--skip-devices")
            .arg("--user-xattrs")
            .arg(format!("--digest-store={}", paths.store_dir().display()))
            .arg(&box_paths.rootfs_path)
            .arg(&box_paths.cfs_path),
    )?;

    meta.built = true;
    meta.mounted = false;
    meta.last_built_at = Some(now_string()?);
    meta.save(&box_paths.metadata_path)?;

    let colors = colors_enabled();
    println!("{} {}", style_action("built", colors), style_title(&args.name, colors));
    println!("  {:<12} {}", "image", image_ref);
    println!("  {:<12} {}", "rootfs", box_paths.rootfs_path.display());
    println!("  {:<12} {}", "cfs", box_paths.cfs_path.display());
    println!("  {:<12} {}", "store", paths.store_dir().display());
    Ok(())
}

fn build_containerfile(name: &str, box_paths: &crate::paths::BoxPaths) -> Result<String> {
    let tag = format!("shellbox-build-{name}:latest");
    run_command(
        Command::new("podman")
            .arg("build")
            .arg("-t")
            .arg(&tag)
            .arg("-f")
            .arg(&box_paths.containerfile_path)
            .arg(&box_paths.dir),
    )?;
    Ok(format!("localhost/{tag}"))
}

// ===========================================================================
// mount / unmount
// ===========================================================================

pub fn cmd_mount(args: NameArgs) -> Result<()> {
    require_root("mount")?;

    let paths = Paths::new()?;
    paths.ensure_base_dirs()?;
    let box_paths = paths.box_paths(&args.name);
    if !box_paths.manifest_path.exists() {
        bail!("box '{}' does not exist", args.name);
    }

    let mut meta = BoxMetadata::load(&box_paths.metadata_path).unwrap_or_default();
    if !meta.built || !box_paths.cfs_path.exists() {
        bail!("box '{}' is not built", args.name);
    }

    std::fs::create_dir_all(&box_paths.mount_path)
        .with_context(|| format!("failed to create {}", box_paths.mount_path.display()))?;

    if is_mountpoint(&box_paths.mount_path) {
        meta.mounted = true;
        meta.save(&box_paths.metadata_path)?;
        let colors = colors_enabled();
        println!("{} {}", style_action("mounted", colors), style_title(&args.name, colors));
        println!("  {:<12} {}", "mount", box_paths.mount_path.display());
        println!("  {:<12} {}", "status", "already mounted");
        return Ok(());
    }

    chown_mount_dir_to_sudo_user(&box_paths.mount_path)?;

    run_command(
        Command::new("mount")
            .arg("-t")
            .arg("composefs")
            .arg("-o")
            .arg(format!("basedir={}", paths.store_dir().display()))
            .arg(&box_paths.cfs_path)
            .arg(&box_paths.mount_path),
    )?;

    meta.mounted = true;
    meta.save(&box_paths.metadata_path)?;
    let colors = colors_enabled();
    println!("{} {}", style_action("mounted", colors), style_title(&args.name, colors));
    println!("  {:<12} {}", "mount", box_paths.mount_path.display());
    println!("  {:<12} {}", "store", paths.store_dir().display());
    Ok(())
}

pub fn cmd_unmount(args: NameArgs) -> Result<()> {
    require_root("unmount")?;

    let paths = Paths::new()?;
    let box_paths = paths.box_paths(&args.name);
    if !box_paths.manifest_path.exists() {
        bail!("box '{}' does not exist", args.name);
    }

    let mut meta = BoxMetadata::load(&box_paths.metadata_path).unwrap_or_default();
    if !is_mountpoint(&box_paths.mount_path) {
        meta.mounted = false;
        meta.save(&box_paths.metadata_path)?;
        let colors = colors_enabled();
        println!("{} {}", style_action("unmounted", colors), style_title(&args.name, colors));
        println!("  {:<12} {}", "status", "already unmounted");
        return Ok(());
    }

    run_command(Command::new("umount").arg(&box_paths.mount_path))?;
    meta.mounted = false;
    meta.save(&box_paths.metadata_path)?;
    let colors = colors_enabled();
    println!("{} {}", style_action("unmounted", colors), style_title(&args.name, colors));
    println!("  {:<12} {}", "mount", box_paths.mount_path.display());
    Ok(())
}

// ===========================================================================
// run / shell / enter
// ===========================================================================

pub fn cmd_run(args: RunArgs) -> Result<()> {
    let paths = Paths::new()?;
    paths.ensure_base_dirs()?;
    let box_paths = paths.box_paths(&args.name);
    if !box_paths.manifest_path.exists() {
        bail!("box '{}' does not exist", args.name);
    }
    let manifest = require_manifest(&box_paths)?;
    let meta = BoxMetadata::load(&box_paths.metadata_path).unwrap_or_default();
    ensure_runtime_ready(&args.name, &box_paths, &meta)?;

    let env = manifest.shell_env();
    let status = run_in_box(&box_paths.mount_path, &env, &args.cmd)?;
    let code = status.code().unwrap_or(1);
    std::process::exit(code);
}

pub fn cmd_shell(args: NameArgs) -> Result<()> {
    let paths = Paths::new()?;
    paths.ensure_base_dirs()?;
    let box_paths = paths.box_paths(&args.name);
    if !box_paths.manifest_path.exists() {
        bail!("box '{}' does not exist", args.name);
    }
    let manifest = require_manifest(&box_paths)?;
    let meta = BoxMetadata::load(&box_paths.metadata_path).unwrap_or_default();
    ensure_runtime_ready(&args.name, &box_paths, &meta)?;

    let tools = normalize_tools(manifest.shell.tools.clone())?;
    if tools.is_empty() {
        bail!(
            "box '{}' has no shell tools configured\nadd tools to {}",
            args.name,
            box_paths.manifest_path.display()
        );
    }

    let env = manifest.shell_env();
    let session_dir = create_shell_session(&paths, &args.name, &tools, &env)?;
    let status = run_host_shell(&args.name, &session_dir.path().join("bin"), &env)?;
    let code = status.code().unwrap_or(1);
    drop(session_dir);
    std::process::exit(code);
}

pub fn cmd_enter(args: NameArgs) -> Result<()> {
    let paths = Paths::new()?;
    paths.ensure_base_dirs()?;
    let box_paths = paths.box_paths(&args.name);
    if !box_paths.manifest_path.exists() {
        bail!("box '{}' does not exist", args.name);
    }
    let manifest = require_manifest(&box_paths)?;
    let meta = BoxMetadata::load(&box_paths.metadata_path).unwrap_or_default();
    ensure_runtime_ready(&args.name, &box_paths, &meta)?;

    let shell = default_enter_shell(&box_paths.mount_path);
    let cmd = vec![shell];
    let env = manifest.shell_env();
    let status = run_in_box(&box_paths.mount_path, &env, &cmd)?;
    let code = status.code().unwrap_or(1);
    std::process::exit(code);
}

// ===========================================================================
// rm / rename
// ===========================================================================

pub fn cmd_rm(args: RmArgs) -> Result<()> {
    let paths = Paths::new()?;
    let box_paths = paths.box_paths(&args.name);

    let manifest_exists = box_paths.manifest_path.exists();
    let state_exists = box_paths.state_dir.exists();

    if !manifest_exists && !state_exists {
        let colors = colors_enabled();
        println!("{} {}", style_action("removed", colors), style_title(&args.name, colors));
        println!("  {:<12} {}", "status", "already absent");
        return Ok(());
    }

    if is_mountpoint(&box_paths.mount_path) {
        bail!(
            "box '{}' is mounted at {} (unmount it first)",
            args.name,
            box_paths.mount_path.display()
        );
    }
    if let Ok(meta) = BoxMetadata::load(&box_paths.metadata_path) {
        if meta.mounted {
            bail!("box '{}' is marked mounted; unmount it first", args.name);
        }
    }

    // Derived artifacts always go.
    if state_exists {
        remove_tree_force(&box_paths.state_dir)?;
    }

    let colors = colors_enabled();

    if args.purge && manifest_exists {
        // Removing a symlinked manifest dir: only the symlink should go, not
        // the target's contents. `rm -rf` on a symlink path unlinks it, but be
        // explicit so we never traverse into the real directory.
        let symlink_meta = std::fs::symlink_metadata(&box_paths.dir);
        let is_symlink = symlink_meta
            .as_ref()
            .map(|m| m.file_type().is_symlink())
            .unwrap_or(false);
        if is_symlink && !args.force {
            bail!(
                "box '{}' is a symlink; pass --force to remove the symlink (the target is left untouched)",
                args.name
            );
        }
        if is_symlink {
            std::fs::remove_file(&box_paths.dir)
                .with_context(|| format!("failed to remove symlink {}", box_paths.dir.display()))?;
        } else {
            remove_tree_force(&box_paths.dir)?;
        }
    }

    println!("{} {}", style_action("removed", colors), style_title(&args.name, colors));
    if state_exists {
        println!("  {:<12} {}", "state", box_paths.state_dir.display());
    }
    if args.purge && manifest_exists {
        println!("  {:<12} {}", "manifest", box_paths.dir.display());
    }
    if !args.purge && manifest_exists {
        println!("  {:<12} {}", "kept", format!("manifest at {}", box_paths.dir.display()));
    }

    // Note any dangling exports so the user can clean them up.
    let owned = scan_exports(&paths)?
        .into_iter()
        .filter(|(_, r)| r.box_name == args.name)
        .count();
    if owned > 0 {
        println!(
            "  {:<12} {} export(s) still reference this box (use `shellbox unexport --all --box {}`)",
            "note", owned, args.name
        );
    }
    Ok(())
}

pub fn cmd_rename(args: RenameArgs) -> Result<()> {
    config::validate_name(&args.new_name)?;

    let paths = Paths::new()?;
    let old = paths.box_paths(&args.old_name);
    let new = paths.box_paths(&args.new_name);

    if !old.manifest_path.exists() {
        bail!("box '{}' does not exist", args.old_name);
    }
    if new.dir.exists() {
        bail!("a box named '{}' already exists", args.new_name);
    }
    if is_mountpoint(&old.mount_path) {
        bail!(
            "box '{}' is mounted; unmount it before renaming",
            args.old_name
        );
    }

    // Move authored dir (handles the symlink case: mv renames the link itself).
    std::fs::rename(&old.dir, &new.dir)
        .with_context(|| format!("failed to rename {} -> {}", old.dir.display(), new.dir.display()))?;

    // Move derived state.
    if old.state_dir.exists() {
        std::fs::create_dir_all(old.state_dir.parent().unwrap_or(&paths.state_dir))?;
        std::fs::rename(&old.state_dir, &new.state_dir)
            .with_context(|| format!("failed to rename {} -> {}", old.state_dir.display(), new.state_dir.display()))?;
    }

    // Update the manifest's `name` field if present.
    let manifest = BoxManifest::load_from(&new.manifest_path)?;
    if manifest.name.as_deref() != Some(args.new_name.as_str()) {
        let mut updated = manifest;
        updated.name = Some(args.new_name.clone());
        updated.save(&new.manifest_path)?;
    }

    // Rewrite exports owned by this box (regenerate wrappers with the new name).
    let env = {
        let m = BoxManifest::load_from(&new.manifest_path)?;
        m.shell_env()
    };
    let records = scan_exports(&paths)?;
    let mut rewritten = 0;
    for (tool, record) in records {
        if record.box_name != args.old_name {
            continue;
        }
        let target = paths.exports_bin_dir().join(&tool);
        write_wrapper_script(&target, &args.new_name, &tool, &env)?;
        save_export_record(
            &paths.exports_metadata_dir().join(format!("{tool}.json")),
            &ExportRecord {
                box_name: args.new_name.clone(),
                command: tool,
            },
        )?;
        rewritten += 1;
    }

    let colors = colors_enabled();
    println!(
        "{} {} -> {}",
        style_action("renamed", colors),
        style_title(&args.old_name, colors),
        style_title(&args.new_name, colors)
    );
    println!("  {:<12} {}", "manifest", new.dir.display());
    println!("  {:<12} {}", "state", new.state_dir.display());
    if rewritten > 0 {
        println!("  {:<12} {}", "exports", rewritten);
    }
    Ok(())
}

// ===========================================================================
// list / inspect
// ===========================================================================

pub fn cmd_list() -> Result<()> {
    let paths = Paths::new()?;
    paths.ensure_base_dirs()?;

    let mut entries: Vec<_> = std::fs::read_dir(paths.boxes_dir())?
        .filter_map(|e| e.ok())
        .filter(|e| e.path().join("shellbox.toml").exists())
        .collect();
    entries.sort_by_key(|e| e.file_name());

    if entries.is_empty() {
        println!("no boxes");
        return Ok(());
    }

    let colors = colors_enabled();
    for entry in entries {
        let name = entry.file_name().to_string_lossy().to_string();
        let box_paths = paths.box_paths(&name);
        let manifest = match BoxManifest::load_from(&box_paths.manifest_path) {
            Ok(m) => m,
            Err(e) => {
                eprintln!("warning: skipping '{}': {e}", name);
                continue;
            }
        };
        let meta = BoxMetadata::load(&box_paths.metadata_path).unwrap_or_default();

        let built_live = box_paths.cfs_path.exists();
        let mounted_live = is_mountpoint(&box_paths.mount_path);
        let status = inspect_status(mounted_live, built_live);
        let source = describe_source(&manifest, &box_paths);

        println!(
            "{} {}",
            style_title(&name, colors),
            style_status_badge(status, colors)
        );
        println!("  {:<12} {}", "source", source);
        println!(
            "  {:<12} {}",
            "built",
            style_recorded_state(meta.built, built_live, colors)
        );
        println!(
            "  {:<12} {}",
            "mounted",
            style_recorded_state(meta.mounted, mounted_live, colors)
        );
        if !manifest.shell.tools.is_empty() {
            println!("  {:<12} {}", "tools", manifest.shell.tools.join(", "));
        }
        println!();
    }

    Ok(())
}

pub fn cmd_inspect(args: NameArgs) -> Result<()> {
    let paths = Paths::new()?;
    let box_paths = paths.box_paths(&args.name);

    if !box_paths.manifest_path.exists() {
        bail!("box '{}' does not exist", args.name);
    }

    let manifest = require_manifest(&box_paths)?;
    let meta = BoxMetadata::load(&box_paths.metadata_path).unwrap_or_default();
    let mounted_live = is_mountpoint(&box_paths.mount_path);
    let built_live = box_paths.cfs_path.exists();
    let colors = colors_enabled();
    let status = inspect_status(mounted_live, built_live);

    println!(
        "{} {}",
        style_title(&args.name, colors),
        style_status_badge(status, colors)
    );
    println!("{} {}", style_label("source", colors), describe_source(&manifest, &box_paths));
    if manifest.image.is_some() {
        println!("{} image", style_label("type", colors));
    } else {
        println!("{} containerfile", style_label("type", colors));
    }
    println!();

    println!("{}", style_section("shell", colors));
    if manifest.shell.tools.is_empty() {
        println!("  {:<12} none", "tools");
    } else {
        println!("  {:<12} {}", "tools", manifest.shell.tools.join(", "));
    }
    if manifest.shell.env.is_empty() {
        println!("  {:<12} none", "env");
    } else {
        for (k, v) in &manifest.shell.env {
            println!("  {:<12} {}={}", "env", k, v);
        }
    }
    println!();

    println!("{}", style_section("state", colors));
    println!(
        "  {:<12} {}",
        "defined",
        style_bool(true, colors)
    );
    println!(
        "  {:<12} {}",
        "built",
        style_recorded_state(meta.built, built_live, colors)
    );
    println!(
        "  {:<12} {}",
        "mounted",
        style_recorded_state(meta.mounted, mounted_live, colors)
    );
    println!();

    println!("{}", style_section("paths", colors));
    println!("  {:<12} {}", "box", box_paths.dir.display());
    println!("  {:<12} {}", "manifest", box_paths.manifest_path.display());
    if box_paths.containerfile_path.exists() {
        println!("  {:<12} {}", "containerfile", box_paths.containerfile_path.display());
    }
    println!("  {:<12} {}", "metadata", box_paths.metadata_path.display());
    println!("  {:<12} {}", "image", box_paths.cfs_path.display());
    println!("  {:<12} {}", "rootfs", box_paths.rootfs_path.display());
    println!("  {:<12} {}", "mount", box_paths.mount_path.display());
    println!();

    println!(
        "{} {}",
        style_label("last built", colors),
        format_last_built_at(meta.last_built_at.as_deref())
    );

    Ok(())
}

fn describe_source(manifest: &BoxManifest, box_paths: &crate::paths::BoxPaths) -> String {
    if let Some(image) = &manifest.image {
        format!("image · {image}")
    } else {
        format!("containerfile · {}", box_paths.containerfile_path.display())
    }
}

// ===========================================================================
// export / unexport / list-exports
// ===========================================================================

pub fn cmd_export(args: ExportArgs) -> Result<()> {
    config::validate_name(&args.name)?;

    let paths = Paths::new()?;
    paths.ensure_base_dirs()?;
    let box_paths = paths.box_paths(&args.name);
    if !box_paths.manifest_path.exists() {
        bail!("box '{}' does not exist", args.name);
    }
    let manifest = require_manifest(&box_paths)?;

    let commands = resolve_export_commands(&manifest, &args)?;
    let env = manifest.shell_env();

    let mut exported = Vec::new();
    for cmd in &commands {
        exported.push(export_one_command(&paths, &args.name, cmd, &env, args.force)?);
    }

    let colors = colors_enabled();
    if commands.len() == 1 {
        println!("{} {}", style_action("exported", colors), style_title(&commands[0], colors));
        println!("  {:<12} {}", "target", exported[0].display());
        println!("  {:<12} {}", "box", args.name);
    } else {
        println!("{} {}", style_action("exported", colors), style_title(&args.name, colors));
        println!("  {:<12} {}", "count", commands.len());
        println!("  {:<12} {}", "bin", paths.exports_bin_dir().display());
        println!("  {:<12} {}", "tools", commands.join(", "));
    }
    Ok(())
}

pub fn cmd_unexport(args: UnexportArgs) -> Result<()> {
    let paths = Paths::new()?;
    paths.ensure_base_dirs()?;

    match (args.tool.as_deref(), args.all) {
        (Some(tool), false) => {
            let removed = remove_export(&paths, tool)?;
            let colors = colors_enabled();
            match removed {
                Some(owner) => {
                    println!("{} {}", style_action("unexported", colors), style_title(tool, colors));
                    println!("  {:<12} {}", "box", owner);
                }
                None => {
                    println!("{} {}", style_action("unexported", colors), style_title(tool, colors));
                    println!("  {:<12} {}", "status", "no metadata (removed wrapper if present)");
                }
            }
        }
        (None, true) => {
            let records = scan_exports(&paths)?;
            let selected: Vec<(String, ExportRecord)> = match &args.box_name {
                Some(name) => records.into_iter().filter(|(_, r)| &r.box_name == name).collect(),
                None => records,
            };

            if selected.is_empty() {
                let colors = colors_enabled();
                let scope = args
                    .box_name
                    .map(|n| format!("owned by box '{}'", n))
                    .unwrap_or_else(|| "to remove".to_string());
                println!("{} no exports {}", style_action("unexported", colors), scope);
                return Ok(());
            }

            let mut count = 0;
            for (tool, _) in &selected {
                remove_export(&paths, tool)?;
                count += 1;
            }

            let colors = colors_enabled();
            println!("{} {}", style_action("unexported", colors), style_title("all", colors));
            println!("  {:<12} {}", "count", count);
            println!("  {:<12} {}", "bin", paths.exports_bin_dir().display());
        }
        (Some(_), true) => bail!("cannot combine a tool name with --all"),
        (None, false) => bail!("specify a tool name or --all"),
    }
    Ok(())
}

pub fn cmd_list_exports() -> Result<()> {
    let paths = Paths::new()?;
    paths.ensure_base_dirs()?;

    let mut records = scan_exports(&paths)?;
    records.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| a.1.box_name.cmp(&b.1.box_name)));

    let colors = colors_enabled();
    if records.is_empty() {
        println!("no exports");
        return Ok(());
    }

    for (tool, record) in &records {
        println!(
            "{} {}",
            style_title(tool, colors),
            style_section(&format!("({})", record.box_name), colors)
        );
        let target = paths.exports_bin_dir().join(tool);
        println!("  {:<12} {}", "target", target.display());
        println!("  {:<12} {}", "box", record.box_name);
    }
    Ok(())
}

fn resolve_export_commands(manifest: &BoxManifest, args: &ExportArgs) -> Result<Vec<String>> {
    let commands = match (&args.cmd, args.all) {
        (Some(cmd), false) => vec![cmd.clone()],
        (None, true) => {
            if manifest.shell.tools.is_empty() {
                bail!(
                    "box has no shell tools configured\nadd tools to the manifest before exporting"
                );
            }
            manifest.shell.tools.clone()
        }
        _ => bail!("exactly one of <cmd> or --all is required"),
    };
    normalize_tools(commands)
}

fn export_one_command(
    paths: &Paths,
    box_name: &str,
    cmd: &str,
    env_vars: &[(String, String)],
    force: bool,
) -> Result<PathBuf> {
    config::validate_tool_name(cmd)?;

    let target = paths.exports_bin_dir().join(cmd);
    let meta_path = paths.exports_metadata_dir().join(format!("{cmd}.json"));

    if meta_path.exists() {
        let existing = load_export_record(&meta_path)?;
        if existing.box_name != box_name && !force {
            bail!(
                "command '{}' is already exported by box '{}'\nre-run with --force to replace it",
                cmd,
                existing.box_name
            );
        }
    } else if target.exists() && !force {
        bail!(
            "export target already exists: {}\nre-run with --force to replace it",
            target.display()
        );
    }

    write_wrapper_script(&target, box_name, cmd, env_vars)?;
    save_export_record(
        &meta_path,
        &ExportRecord {
            box_name: box_name.to_string(),
            command: cmd.to_string(),
        },
    )?;

    Ok(target)
}

fn load_export_record(path: &Path) -> Result<ExportRecord> {
    let data = std::fs::read(path).with_context(|| format!("failed to read {}", path.display()))?;
    let record = serde_json::from_slice(&data)
        .with_context(|| format!("failed to parse {}", path.display()))?;
    Ok(record)
}

fn save_export_record(path: &Path, record: &ExportRecord) -> Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .with_context(|| format!("failed to create {}", parent.display()))?;
    }
    let data = serde_json::to_vec_pretty(record)?;
    std::fs::write(path, data).with_context(|| format!("failed to write {}", path.display()))?;
    Ok(())
}

fn scan_exports(paths: &Paths) -> Result<Vec<(String, ExportRecord)>> {
    let dir = paths.exports_metadata_dir();
    let mut out = Vec::new();
    let entries = match std::fs::read_dir(&dir) {
        Ok(e) => e,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(out),
        Err(e) => return Err(e).with_context(|| format!("failed to read {}", dir.display())),
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().and_then(|s| s.to_str()) != Some("json") {
            continue;
        }
        let Some(stem) = path.file_stem().and_then(|s| s.to_str()) else {
            continue;
        };
        let record = match load_export_record(&path) {
            Ok(r) => r,
            Err(e) => {
                eprintln!("warning: skipping {}: {e}", path.display());
                continue;
            }
        };
        out.push((stem.to_string(), record));
    }
    Ok(out)
}

fn remove_export(paths: &Paths, tool: &str) -> Result<Option<String>> {
    let target = paths.exports_bin_dir().join(tool);
    let meta_path = paths.exports_metadata_dir().join(format!("{tool}.json"));

    let owner = if meta_path.exists() {
        let record = load_export_record(&meta_path)?;
        std::fs::remove_file(&meta_path)
            .with_context(|| format!("failed to remove {}", meta_path.display()))?;
        Some(record.box_name)
    } else {
        None
    };

    if target.exists() {
        std::fs::remove_file(&target)
            .with_context(|| format!("failed to remove {}", target.display()))?;
    }

    Ok(owner)
}

// ===========================================================================
// migrate (legacy config.json -> vendored shellbox.toml)
// ===========================================================================

#[derive(Deserialize)]
struct LegacyConfig {
    source: LegacySource,
    #[serde(default)]
    shell: LegacyShell,
    #[serde(default)]
    manifest_dir: Option<PathBuf>,
}

#[derive(Deserialize)]
#[serde(tag = "kind", content = "value", rename_all = "snake_case")]
enum LegacySource {
    ImageRef(String),
    ContainerfilePath(PathBuf),
}

#[derive(Default, Deserialize)]
struct LegacyShell {
    #[serde(default)]
    tools: Vec<String>,
    #[serde(default)]
    env: std::collections::BTreeMap<String, String>,
}

#[derive(Default, Deserialize)]
struct LegacyMetadata {
    #[serde(default)]
    built: bool,
    #[serde(default)]
    last_built_at: Option<String>,
}

pub fn cmd_migrate() -> Result<()> {
    let paths = Paths::new()?;
    paths.ensure_base_dirs()?;

    let entries: Vec<_> = std::fs::read_dir(paths.boxes_dir())?
        .filter_map(|e| e.ok())
        .filter(|e| e.path().is_dir())
        .collect();

    let mut migrated = 0;
    let mut skipped = 0;
    let mut failed = 0;

    for entry in entries {
        let name = entry.file_name().to_string_lossy().to_string();
        let box_paths = paths.box_paths(&name);
        let legacy_config = box_paths.dir.join("config.json");

        // Already migrated (or never legacy)?
        if box_paths.manifest_path.exists() {
            skipped += 1;
            continue;
        }
        if !legacy_config.exists() {
            skipped += 1;
            continue;
        }

        if let Err(e) = migrate_one(&paths, &name, &box_paths) {
            eprintln!("error migrating '{}': {e}", name);
            failed += 1;
            continue;
        }
        println!("migrated '{}'", name);
        migrated += 1;
    }

    println!();
    println!("migration complete: {} migrated, {} skipped, {} failed", migrated, skipped, failed);
    Ok(())
}

fn migrate_one(paths: &Paths, name: &str, box_paths: &crate::paths::BoxPaths) -> Result<()> {
    let legacy_config_path = box_paths.dir.join("config.json");
    let legacy_meta_path = box_paths.dir.join("metadata.json");

    // Legacy mountpoint lived at state/mounts/<name>.
    let legacy_mount = paths.state_dir.join("mounts").join(name);
    if is_mountpoint(&legacy_mount) {
        bail!("box is still mounted at {}; unmount it before migrating", legacy_mount.display());
    }

    let data = std::fs::read(&legacy_config_path)
        .with_context(|| format!("failed to read {}", legacy_config_path.display()))?;
    let legacy: LegacyConfig = serde_json::from_slice(&data)
        .with_context(|| format!("failed to parse {}", legacy_config_path.display()))?;

    let legacy_meta: LegacyMetadata = std::fs::read(&legacy_meta_path)
        .ok()
        .and_then(|d| serde_json::from_slice(&d).ok())
        .unwrap_or_default();

    let mut manifest = BoxManifest {
        name: Some(name.to_string()),
        ..Default::default()
    };
    let mut containerfile_src: Option<PathBuf> = None;
    match legacy.source {
        LegacySource::ImageRef(image) => manifest.image = Some(image),
        LegacySource::ContainerfilePath(p) => containerfile_src = Some(p),
    }
    manifest.shell.tools = legacy.shell.tools;

    // Freeze {manifest_dir} tokens to literal absolute values.
    for (k, v) in legacy.shell.env {
        let expanded = match &legacy.manifest_dir {
            Some(d) => v.replace("{manifest_dir}", &d.display().to_string()),
            None => {
                if v.contains("{manifest_dir}") {
                    eprintln!(
                        "warning: '{}' has {{manifest_dir}} token but no manifest_dir was recorded; leaving the literal token in place",
                        name
                    );
                }
                v
            }
        };
        manifest.shell.env.insert(k, expanded);
    }

    manifest.save(&box_paths.manifest_path)?;

    // Vendor the Containerfile if needed.
    if let Some(src) = containerfile_src {
        if src.exists() {
            std::fs::copy(&src, &box_paths.containerfile_path).with_context(|| {
                format!("failed to copy {} to {}", src.display(), box_paths.containerfile_path.display())
            })?;
        } else {
            eprintln!(
                "warning: '{}' references containerfile {} which no longer exists",
                name,
                src.display()
            );
        }
    }

    // Move derived artifacts into state/<name>/.
    std::fs::create_dir_all(&box_paths.state_dir)?;
    move_path(&box_paths.dir.join("image.cfs"), &box_paths.cfs_path)?;
    move_path(&box_paths.dir.join("rootfs"), &box_paths.rootfs_path)?;
    if legacy_mount.exists() {
        // legacy_mount -> state/<name>/mount
        move_path(&legacy_mount, &box_paths.mount_path)?;
    }

    let new_meta = BoxMetadata {
        built: legacy_meta.built,
        mounted: false,
        last_built_at: legacy_meta.last_built_at,
    };
    new_meta.save(&box_paths.metadata_path)?;

    // Remove legacy files.
    let _ = std::fs::remove_file(&legacy_config_path);
    let _ = std::fs::remove_file(&legacy_meta_path);

    Ok(())
}

fn move_path(src: &Path, dst: &Path) -> Result<()> {
    if !src.exists() {
        return Ok(());
    }
    if let Some(parent) = dst.parent() {
        std::fs::create_dir_all(parent)?;
    }
    // Try a cheap rename; fall back to a recursive copy+delete across devices.
    if std::fs::rename(src, dst).is_ok() {
        return Ok(());
    }
    run_command(
        Command::new("cp")
            .arg("-a")
            .arg(src)
            .arg(dst),
    )?;
    if src.is_dir() {
        remove_tree_force(src)?;
    } else {
        let _ = std::fs::remove_file(src);
    }
    Ok(())
}

// ===========================================================================
// runtime (bwrap)
// ===========================================================================

fn ensure_runtime_ready(name: &str, box_paths: &crate::paths::BoxPaths, meta: &BoxMetadata) -> Result<()> {
    if !meta.built || !box_paths.cfs_path.exists() {
        bail!("box '{}' is not built", name);
    }
    if !is_mountpoint(&box_paths.mount_path) {
        bail!("box '{}' is not mounted\nrun: sudo shellbox mount {}", name, name);
    }
    Ok(())
}

fn export_image_rootfs(image_ref: &str, rootfs_path: &Path) -> Result<()> {
    let cid = command_output(Command::new("podman").arg("create").arg(image_ref))?;
    let result = (|| -> Result<()> {
        run_command(
            Command::new("bash").arg("-lc").arg(format!(
                "podman export {cid} | tar --no-same-owner --no-same-permissions -C '{}' -xf -",
                rootfs_path.display()
            )),
        )
    })();
    let _ = run_command(Command::new("podman").arg("rm").arg(&cid));
    result
}

fn normalize_rootfs_permissions(rootfs_path: &Path) -> Result<()> {
    run_command(
        Command::new("bash").arg("-lc").arg(format!(
            "find '{}' -xdev ! -readable -type f -exec chmod u+r '{{}}' + && find '{}' -xdev ! -readable -type d -exec chmod u+rx '{{}}' +",
            rootfs_path.display(),
            rootfs_path.display()
        )),
    )
}

fn normalize_tools(tools: Vec<String>) -> Result<Vec<String>> {
    let mut normalized = Vec::new();
    for tool in tools {
        config::validate_tool_name(&tool)?;
        if !normalized.iter().any(|existing: &String| existing == &tool) {
            normalized.push(tool);
        }
    }
    Ok(normalized)
}

fn create_shell_session(
    paths: &Paths,
    box_name: &str,
    tools: &[String],
    env_vars: &[(String, String)],
) -> Result<TempDir> {
    let session = Builder::new()
        .prefix(&format!("{box_name}-"))
        .tempdir_in(paths.sessions_dir())?;
    let bin_dir = session.path().join("bin");
    std::fs::create_dir_all(&bin_dir)
        .with_context(|| format!("failed to create {}", bin_dir.display()))?;
    for tool in tools {
        write_wrapper_script(&bin_dir.join(tool), box_name, tool, env_vars)?;
    }
    Ok(session)
}

fn run_host_shell(
    box_name: &str,
    wrapper_dir: &Path,
    _env_vars: &[(String, String)],
) -> Result<std::process::ExitStatus> {
    let shell = std::env::var_os("SHELL").unwrap_or_else(|| OsString::from("/bin/sh"));
    let path = prepend_path(wrapper_dir)?;

    let mut command = Command::new(shell);
    command.env("PATH", path);
    command.env("SHELLBOX_NAME", box_name);
    command.env("SHELLBOX_EXPORT_MODE", "ephemeral");
    command.env("SHELLBOX_WRAPPER_DIR", wrapper_dir);
    // NOTE: declared box env vars (`[shell.env]`) are deliberately NOT applied
    // to the session here. They are inlined into each tool's wrapper script
    // (see `write_wrapper_script`), so they take effect only when a box tool
    // is actually invoked — never leaking onto unrelated programs run in the
    // session. This lets multiple boxes coexist in one shell: e.g. entering
    // the nvim box no longer redirects XDG for `git`, `ls`, etc.
    run_command_inherit(&mut command)
}

fn prepend_path(prefix: &Path) -> Result<OsString> {
    let mut value = prefix.as_os_str().to_os_string();
    if let Some(current) = std::env::var_os("PATH") {
        value.push(":");
        value.push(current);
    }
    Ok(value)
}

/// Build the `PATH` value for a box runtime: forward host PATH entries that
/// will resolve inside the bwrap, then append standard system dirs as fallback.
///
/// An entry is kept iff all of the following hold:
/// - it is under `$HOME` (always bound into the box) or exists in the box
///   rootfs (otherwise it would dangle), and
/// - it is NOT a shellbox-managed wrapper directory. The exports and sessions
///   dirs hold wrappers that call `shellbox run <box>`; forwarding them into a
///   box runtime would shadow the box's own binaries and recurse forever.
///
/// Standard system dirs are always appended as a fallback. Host entries
/// precede them so user-installed tools take precedence over same-named box
/// binaries. Order is preserved and duplicates are removed.
fn forwarded_path(home: &Path, mount_path: &Path) -> Result<OsString> {
    const SYSTEM_FALLBACK: &str =
        "/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin";

    // Shellbox-managed subtrees that must never be forwarded (recursion risk).
    let skip_prefixes: [PathBuf; 2] = [
        home.join(".local/share/shellbox"),
        home.join(".local/state/shellbox"),
    ];

    let mut kept: Vec<String> = Vec::new();
    let mut seen: std::collections::HashSet<String> = std::collections::HashSet::new();

    if let Some(path) = std::env::var_os("PATH") {
        for raw in std::env::split_paths(&path) {
            let Some(s) = raw.to_str() else { continue };
            let cleaned = s.trim_end_matches('/');
            if cleaned.is_empty() || cleaned == "." {
                continue;
            }
            if !seen.insert(cleaned.to_string()) {
                continue; // dedup, first occurrence wins
            }
            let p = Path::new(cleaned);
            let is_shellbox_internal = skip_prefixes
                .iter()
                .any(|prefix| p.starts_with(prefix));
            if is_shellbox_internal {
                continue;
            }
            let reachable = p.starts_with(home) || mount_path.join(cleaned).exists();
            if reachable {
                kept.push(cleaned.to_string());
            }
        }
    }

    for d in SYSTEM_FALLBACK.split(':') {
        if seen.insert(d.to_string()) {
            kept.push(d.to_string());
        }
    }

    Ok(OsString::from(kept.join(":")))
}

fn write_wrapper_script(
    target: &Path,
    box_name: &str,
    cmd: &str,
    env_vars: &[(String, String)],
) -> Result<()> {
    let shellbox = current_shellbox_invocation();
    let mut lines = String::from("#!/usr/bin/env bash\n");
    // Values are author-supplied literals (no expansion); inline them so
    // wrappers work outside any box shell session.
    for (k, v) in env_vars {
        lines.push_str(&format!("export {}={}\n", k, shell_quote(v)));
    }
    lines.push_str(&format!(
        "exec {} run {} -- {} \"$@\"\n",
        shell_quote(&shellbox),
        shell_quote(box_name),
        shell_quote(cmd),
    ));

    std::fs::write(target, lines).with_context(|| format!("failed to write {}", target.display()))?;
    let mut perms = std::fs::metadata(target)?.permissions();
    perms.set_mode(0o755);
    std::fs::set_permissions(target, perms)?;
    Ok(())
}

fn run_in_box(
    mount_path: &Path,
    env_vars: &[(String, String)],
    cmd: &[String],
) -> Result<std::process::ExitStatus> {
    let home = home_dir()?;
    let cwd = std::env::current_dir().unwrap_or_else(|_| home.clone());
    let chdir = if cwd.starts_with(&home) {
        cwd
    } else {
        home.clone()
    };
    let user = std::env::var("USER").unwrap_or_else(|_| "user".to_string());
    let logname = std::env::var("LOGNAME").unwrap_or_else(|_| user.clone());

    let mut command = Command::new("bwrap");
    command
        .arg("--bind").arg(mount_path).arg("/")
        .arg("--dev-bind").arg("/dev").arg("/dev")
        .arg("--proc").arg("/proc")
        .arg("--share-net")
        .arg("--ro-bind-try").arg("/etc/resolv.conf").arg("/etc/resolv.conf")
        .arg("--ro-bind-try").arg("/etc/hosts").arg("/etc/hosts")
        .arg("--tmpfs").arg("/tmp")
        .arg("--tmpfs").arg("/var")
        .arg("--dir").arg("/var/home")
        .arg("--bind").arg(&home).arg(&home)
        .arg("--chdir").arg(&chdir)
        .arg("--setenv").arg("HOME").arg(&home)
        .arg("--setenv").arg("USER").arg(&user)
        .arg("--setenv").arg("LOGNAME").arg(&logname)
        // Forward the host PATH into the box, so that user-installed tools
        // under $HOME (e.g. `~/.cargo/bin`, `~/.npm-global/bin`, `~/.local/bin`)
        // are visible to box processes — including agents (pi/opencode) that
        // shell out. This matches the host-integration feel of distrobox.
        //
        // We do NOT forward blindly: only entries that will actually resolve
        // inside the bwrap are kept (under $HOME, which is bound in, or present
        // in the box rootfs). Anything else (e.g. /nix/store, /opt/...) would
        // dangle and is dropped.
        //
        // Shellbox-managed wrapper directories (exports/bin, sessions/*/bin)
        // are explicitly excluded: their wrapper scripts invoke
        // `shellbox run <box>` again, so forwarding them into a box runtime
        // would shadow the box's own tools and recurse indefinitely. Only
        // genuine host tool directories are forwarded.
        .arg("--setenv").arg("PATH").arg(forwarded_path(&home, mount_path)?);

    if let Ok(xrd) = std::env::var("XDG_RUNTIME_DIR") {
        command.arg("--bind-try").arg(&xrd).arg(&xrd);
    }
    command.arg("--ro-bind-try").arg("/tmp/.X11-unix").arg("/tmp/.X11-unix");

    // Apply declared box env vars (verbatim) after the defaults so they win.
    for (k, v) in env_vars {
        command.arg("--setenv").arg(k).arg(v);
    }

    for part in cmd {
        command.arg(part);
    }

    run_command_inherit(&mut command)
}

// ===========================================================================
// identity & name resolution injection (build-time)
// ===========================================================================

fn inject_runtime_identity(rootfs: &Path) -> Result<()> {
    let etc = rootfs.join("etc");
    std::fs::create_dir_all(&etc)
        .with_context(|| format!("failed to create {}", etc.display()))?;

    let uid = Uid::current().as_raw();
    let fallback_gid = Gid::current().as_raw();
    let user = User::from_uid(Uid::current())?;
    let primary_gid = user.as_ref().map(|u| u.gid.as_raw()).unwrap_or(fallback_gid);
    let username = user
        .as_ref()
        .map(|u| u.name.clone())
        .filter(|name| !name.is_empty())
        .unwrap_or_else(|| std::env::var("USER").unwrap_or_else(|_| format!("user{uid}")));
    let home = home_dir()?;
    let shell = default_enter_shell(rootfs);
    let gids = current_group_ids(primary_gid)?;

    let mut group_names: Vec<(u32, String)> = Vec::new();
    for gid in &gids {
        let name = Group::from_gid(Gid::from_raw(*gid))?
            .map(|g| g.name)
            .filter(|n| !n.is_empty())
            .unwrap_or_else(|| format!("gid{gid}"));
        group_names.push((*gid, name));
    }

    merge_passwd(&etc.join("passwd"), uid, primary_gid, &username, &home, &shell)?;
    merge_group(&etc.join("group"), &username, &group_names)?;
    ensure_nsswitch_files(&etc.join("nsswitch.conf"))?;
    Ok(())
}

fn inject_name_resolution(rootfs: &Path) -> Result<()> {
    let etc = rootfs.join("etc");
    std::fs::create_dir_all(&etc)
        .with_context(|| format!("failed to create {}", etc.display()))?;
    copy_host_file(Path::new("/etc/resolv.conf"), &etc.join("resolv.conf"))?;
    copy_host_file(Path::new("/etc/hosts"), &etc.join("hosts"))?;
    Ok(())
}

fn inject_desktop_mount_points(rootfs: &Path) -> Result<()> {
    let uid = nix::unistd::Uid::current().as_raw();
    let dir = rootfs.join("run").join("user").join(uid.to_string());
    std::fs::create_dir_all(&dir)
        .with_context(|| format!("failed to create {}", dir.display()))?;
    Ok(())
}

fn copy_host_file(src: &Path, dst: &Path) -> Result<()> {
    match std::fs::read(src) {
        Ok(data) => {
            std::fs::write(dst, data)
                .with_context(|| format!("failed to write {}", dst.display()))?;
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            eprintln!("warning: host file {} not found; skipping", src.display());
        }
        Err(e) => return Err(e).with_context(|| format!("failed to read {}", src.display())),
    }
    Ok(())
}

fn merge_passwd(
    path: &Path,
    uid: u32,
    gid: u32,
    username: &str,
    home: &Path,
    shell: &str,
) -> Result<()> {
    let existing = std::fs::read_to_string(path).unwrap_or_default();
    let mut lines: Vec<String> = existing
        .lines()
        .filter(|line| {
            let mut fields = line.split(':');
            let name = fields.next().unwrap_or("");
            let id = fields.nth(1).and_then(|s| s.parse::<u32>().ok());
            !(name == username || id == Some(uid))
        })
        .map(str::to_string)
        .collect();
    lines.push(format!("{}:x:{}:{}::{}:{}", username, uid, gid, home.display(), shell));
    write_lines(path, &lines)?;
    Ok(())
}

fn merge_group(path: &Path, username: &str, groups: &[(u32, String)]) -> Result<()> {
    let existing = std::fs::read_to_string(path).unwrap_or_default();
    let mut lines: Vec<Vec<String>> = existing
        .lines()
        .filter(|line| !line.is_empty())
        .map(|line| line.split(':').map(str::to_string).collect())
        .collect();

    for (gid, name) in groups {
        if let Some(row) = lines
            .iter_mut()
            .find(|fields| fields.get(2).and_then(|s| s.parse::<u32>().ok()) == Some(*gid))
        {
            let members = row.get_mut(3).unwrap();
            let mut list: Vec<&str> = members.split(',').filter(|s| !s.is_empty()).collect();
            if !list.iter().any(|m| *m == username) {
                list.push(username);
            }
            *members = list.join(",");
        } else {
            lines.push(vec![
                name.clone(),
                "x".to_string(),
                gid.to_string(),
                username.to_string(),
            ]);
        }
    }

    let rendered: Vec<String> = lines.into_iter().map(|fields| fields.join(":")).collect();
    write_lines(path, &rendered)?;
    Ok(())
}

fn ensure_nsswitch_files(path: &Path) -> Result<()> {
    let existing = std::fs::read_to_string(path).unwrap_or_default();
    let passwd_ok = existing.lines().any(|line| line.starts_with("passwd:") && line.contains("files"));
    let group_ok = existing.lines().any(|line| line.starts_with("group:") && line.contains("files"));
    if passwd_ok && group_ok {
        return Ok(());
    }
    let hosts_line = existing
        .lines()
        .find(|line| line.starts_with("hosts:"))
        .unwrap_or("hosts: files dns myhostname")
        .to_string();
    let content = format!("passwd: files\ngroup: files\nshadow: files\n{}\n", hosts_line);
    std::fs::write(path, content).with_context(|| format!("failed to write {}", path.display()))?;
    Ok(())
}

fn write_lines(path: &Path, lines: &[String]) -> Result<()> {
    let mut content = lines.join("\n");
    if !content.is_empty() {
        content.push('\n');
    }
    std::fs::write(path, content).with_context(|| format!("failed to write {}", path.display()))?;
    Ok(())
}

fn current_group_ids(primary_gid: u32) -> Result<Vec<u32>> {
    let output = command_output(Command::new("id").arg("-G"))?;
    let mut gids = Vec::new();
    for raw in output.split_whitespace() {
        let gid: u32 = raw
            .parse()
            .with_context(|| format!("failed to parse gid '{raw}' from `id -G`"))?;
        if !gids.contains(&gid) {
            gids.push(gid);
        }
    }
    if !gids.contains(&primary_gid) {
        gids.insert(0, primary_gid);
    }
    Ok(gids)
}

fn default_enter_shell(root: &Path) -> String {
    if root.join("bin/bash").exists() {
        "/bin/bash".to_string()
    } else {
        "/bin/sh".to_string()
    }
}

// ===========================================================================
// helpers
// ===========================================================================

fn now_string() -> Result<String> {
    let dur = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .context("system clock is before unix epoch")?;
    Ok(dur.as_secs().to_string())
}

#[derive(Clone, Copy)]
enum InspectStatus {
    Defined,
    Built,
    Mounted,
}

fn inspect_status(mounted_live: bool, built_live: bool) -> InspectStatus {
    if mounted_live {
        InspectStatus::Mounted
    } else if built_live {
        InspectStatus::Built
    } else {
        InspectStatus::Defined
    }
}

fn colors_enabled() -> bool {
    std::io::stdout().is_terminal()
        && std::env::var_os("NO_COLOR").is_none()
        && std::env::var("TERM").map(|v| v != "dumb").unwrap_or(true)
}

fn style_title(value: &str, colors: bool) -> String {
    if colors { value.bold().to_string() } else { value.to_string() }
}

fn style_label(value: &str, colors: bool) -> String {
    if colors { value.blue().bold().to_string() } else { value.to_string() }
}

fn style_action(value: &str, colors: bool) -> String {
    if colors {
        format!("{} {}", "✓".green().bold(), value.green().bold())
    } else {
        format!("✓ {value}")
    }
}

fn style_section(value: &str, colors: bool) -> String {
    if colors { value.bright_black().bold().to_string() } else { value.to_string() }
}

fn style_status_badge(status: InspectStatus, colors: bool) -> String {
    match status {
        InspectStatus::Defined => {
            if colors {
                format!("{} {}", "●".yellow().bold(), "defined".yellow().bold())
            } else {
                "* defined".to_string()
            }
        }
        InspectStatus::Built => {
            if colors {
                format!("{} {}", "●".blue().bold(), "built".blue().bold())
            } else {
                "* built".to_string()
            }
        }
        InspectStatus::Mounted => {
            if colors {
                format!("{} {}", "●".green().bold(), "mounted".green().bold())
            } else {
                "* mounted".to_string()
            }
        }
    }
}

fn style_bool(value: bool, colors: bool) -> String {
    match (value, colors) {
        (true, true) => format!("{} {}", "✓".green().bold(), "yes".green()),
        (false, true) => format!("{} {}", "✗".red().bold(), "no".red()),
        (true, false) => "yes".to_string(),
        (false, false) => "no".to_string(),
    }
}

fn style_recorded_state(recorded: bool, live: bool, colors: bool) -> String {
    let summary = if recorded == live {
        style_bool(live, colors)
    } else if colors {
        format!("{} {}", "!".yellow().bold(), "drift".yellow().bold())
    } else {
        "drift".to_string()
    };
    format!(
        "{summary}  {} {}  {} {}",
        style_section("recorded", colors),
        style_bool(recorded, colors),
        style_section("live", colors),
        style_bool(live, colors)
    )
}

fn format_last_built_at(raw: Option<&str>) -> String {
    let Some(raw) = raw else { return "never".to_string() };
    let Ok(secs) = raw.parse::<u64>() else { return raw.to_string() };
    let timestamp = UNIX_EPOCH + Duration::from_secs(secs);
    let absolute = humantime::format_rfc3339_seconds(timestamp).to_string();
    let relative = match SystemTime::now().duration_since(timestamp) {
        Ok(delta) => format!("{} ago", humantime::format_duration(delta)),
        Err(_) => absolute.clone(),
    };
    format!("{absolute} ({relative})")
}

fn is_mountpoint(path: &Path) -> bool {
    Command::new("mountpoint")
        .arg("-q")
        .arg(path)
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn remove_tree_force(path: &Path) -> Result<()> {
    if !path.exists() {
        return Ok(());
    }
    run_command(Command::new("bash").arg("-lc").arg(format!(
        "chmod -R u+rwX '{}' 2>/dev/null || true; rm -rf --one-file-system '{}'",
        path.display(),
        path.display()
    )))
}

fn require_root(verb: &str) -> Result<()> {
    if Uid::effective().is_root() {
        return Ok(());
    }
    bail!("{} requires root\nrun: sudo shellbox {} <name>", verb, verb);
}

fn chown_mount_dir_to_sudo_user(path: &Path) -> Result<()> {
    let uid = std::env::var("SUDO_UID").ok();
    let gid = std::env::var("SUDO_GID").ok();
    if let (Some(uid), Some(gid)) = (uid, gid) {
        let spec = format!("{uid}:{gid}");
        run_command(Command::new("chown").arg(&spec).arg(path))?;
    }
    Ok(())
}

fn home_dir() -> Result<PathBuf> {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .context("HOME is not set")
}

fn current_shellbox_invocation() -> OsString {
    std::env::current_exe()
        .ok()
        .map(|p| p.into_os_string())
        .unwrap_or_else(|| OsString::from("shellbox"))
}

fn shell_quote(s: impl AsRef<std::ffi::OsStr>) -> String {
    let s = s.as_ref().to_string_lossy();
    format!("'{}'", s.replace('\'', "'\"'\"'"))
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ExportRecord {
    box_name: String,
    command: String,
}

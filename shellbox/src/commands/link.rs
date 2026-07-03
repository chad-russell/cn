use super::common::{is_mountpoint, remove_tree_force};
use super::ui::{colors_enabled, style_action, style_title};
use crate::cli::LinkArgs;
use crate::config;
use crate::metadata::BoxMetadata;
use crate::paths::Paths;
use anyhow::{Context, Result, bail};
use std::path::PathBuf;

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

use super::common::{chown_mount_dir_to_sudo_user, is_mountpoint, require_root};
use super::ui::{colors_enabled, style_action, style_title};
use crate::cli::NameArgs;
use crate::metadata::BoxMetadata;
use crate::paths::Paths;
use crate::util::run_command;
use anyhow::{Context, Result, bail};
use std::process::Command;

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
        bail!("box '{}' is not prepared", args.name);
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

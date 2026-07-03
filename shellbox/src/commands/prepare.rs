use super::common::{is_mountpoint, remove_tree_force, require_manifest};
use super::identity::{
    inject_desktop_mount_points, inject_host_exec_mount_points, inject_name_resolution,
    inject_runtime_identity,
};
use super::ui::{colors_enabled, style_action, style_title};
use crate::cli::NameArgs;
use crate::metadata::BoxMetadata;
use crate::paths::Paths;
use crate::util::{command_output, run_command};
use anyhow::{Context, Result, bail};
use std::path::Path;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

pub fn cmd_prepare(args: NameArgs) -> Result<()> {
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
            "box '{}' is mounted at {}\nunmount it before preparing again",
            args.name,
            box_paths.mount_path.display()
        );
    }

    if box_paths.rootfs_path.exists() {
        remove_tree_force(&box_paths.rootfs_path)?;
    }
    std::fs::create_dir_all(&box_paths.rootfs_path)
        .with_context(|| format!("failed to create {}", box_paths.rootfs_path.display()))?;

    let image_ref = manifest.image.clone();

    export_image_rootfs(&image_ref, &box_paths.rootfs_path)?;
    normalize_rootfs_permissions(&box_paths.rootfs_path)?;
    inject_runtime_identity(&box_paths.rootfs_path)?;
    inject_name_resolution(&box_paths.rootfs_path)?;
    inject_desktop_mount_points(&box_paths.rootfs_path)?;
    inject_host_exec_mount_points(&box_paths.rootfs_path, &manifest)?;

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
    println!("{} {}", style_action("prepared", colors), style_title(&args.name, colors));
    println!("  {:<12} {}", "image", image_ref);
    println!("  {:<12} {}", "rootfs", box_paths.rootfs_path.display());
    println!("  {:<12} {}", "cfs", box_paths.cfs_path.display());
    println!("  {:<12} {}", "store", paths.store_dir().display());
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

fn now_string() -> Result<String> {
    let dur = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .context("system clock is before unix epoch")?;
    Ok(dur.as_secs().to_string())
}

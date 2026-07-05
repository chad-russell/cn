use super::common::{normalize_tools, remove_tree_force, require_manifest};
use super::export::sync_box_exports;
use super::identity::{
    inject_desktop_mount_points, inject_host_exec_mount_points, inject_name_resolution,
    inject_runtime_identity,
};
use super::ui::{colors_enabled, style_action, style_title};
use crate::cli::NameArgs;
use crate::metadata::BoxMetadata;
use crate::paths::{BoxPaths, Paths};
use crate::util::{command_output, run_command, run_command_inherit};
use anyhow::{Context, Result, bail};
use std::path::{Path, PathBuf};
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

    if box_paths.rootfs_path.exists() {
        remove_tree_force(&box_paths.rootfs_path)?;
    }
    std::fs::create_dir_all(&box_paths.rootfs_path)
        .with_context(|| format!("failed to create {}", box_paths.rootfs_path.display()))?;

    let image_ref = manifest.image.clone();

    // If the box ships a Containerfile (or Dockerfile), build it into the
    // image ref first. Podman's layer cache makes an unchanged file a
    // near-instant no-op, so we always invoke it.
    let built_containerfile = build_containerfile_if_present(&box_paths, &image_ref)?;

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
    meta.last_built_at = Some(now_string()?);
    meta.save(&box_paths.metadata_path)?;

    // Reconcile persistent exports with the declared tools (last-prepare-wins).
    let tools = normalize_tools(manifest.shell.tools.clone())?;
    let env = manifest.shell_env();
    let report = sync_box_exports(&paths, &args.name, &tools, &env)?;

    let colors = colors_enabled();
    println!(
        "{} {}",
        style_action("prepared", colors),
        style_title(&args.name, colors)
    );
    println!("  {:<12} {}", "image", image_ref);
    if let Some(cf) = built_containerfile {
        println!("  {:<12} {}", "built", cf.display());
    }
    println!("  {:<12} {}", "rootfs", box_paths.rootfs_path.display());
    println!("  {:<12} {}", "cfs", box_paths.cfs_path.display());
    println!("  {:<12} {}", "store", paths.store_dir().display());
    if !report.exported.is_empty() {
        println!("  {:<12} {}", "exported", report.exported.join(", "));
    }
    if !report.removed.is_empty() {
        println!("  {:<12} {}", "unexported", report.removed.join(", "));
    }
    Ok(())
}

/// Build a Containerfile/Dockerfile found in the box dir into `image_ref`.
/// Returns `Some(path)` if a build happened, `None` if no file was present.
fn build_containerfile_if_present(
    box_paths: &BoxPaths,
    image_ref: &str,
) -> Result<Option<PathBuf>> {
    let containerfile = ["Containerfile", "Dockerfile"]
        .into_iter()
        .map(|name| box_paths.dir.join(name))
        .find(|p| p.is_file());

    let Some(containerfile) = containerfile else {
        return Ok(None);
    };

    let status = run_command_inherit(
        Command::new("podman")
            .arg("build")
            .arg("-t")
            .arg(image_ref)
            .arg("-f")
            .arg(&containerfile)
            .arg(&box_paths.dir),
    )
    .with_context(|| format!("failed to build image from {}", containerfile.display()))?;

    if !status.success() {
        bail!(
            "image build failed (exit {}) for {}",
            status
                .code()
                .map(|c| c.to_string())
                .unwrap_or_else(|| "signal".into()),
            containerfile.display()
        );
    }

    Ok(Some(containerfile))
}

fn export_image_rootfs(image_ref: &str, rootfs_path: &Path) -> Result<()> {
    let cid = command_output(Command::new("podman").arg("create").arg(image_ref))?;
    let result = run_command(Command::new("bash").arg("-lc").arg(format!(
        "podman export {cid} | tar --no-same-owner --no-same-permissions -C '{}' -xf -",
        rootfs_path.display()
    )));
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

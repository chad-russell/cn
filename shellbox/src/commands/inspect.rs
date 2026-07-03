use super::common::{describe_source, is_mountpoint, require_manifest};
use super::ui::{
    colors_enabled, inspect_status, style_bool, style_label, style_recorded_state, style_section,
    style_status_badge, style_title, format_last_built_at,
};
use crate::cli::NameArgs;
use crate::metadata::BoxMetadata;
use crate::paths::Paths;
use anyhow::{Result, bail};

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
    println!("{} image", style_label("type", colors));
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

    println!("{}", style_section("host", colors));
    if manifest.host.tools.is_empty() {
        println!("  {:<12} none", "tools");
    } else {
        println!(
            "  {:<12} {}",
            "tools",
            manifest.host.tools.join(", "),
        );
        println!("  {:<12} {} (run only; forwarded via systemd-run --user)", "note", " ");
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
        "prepared",
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
    println!("  {:<12} {}", "metadata", box_paths.metadata_path.display());
    println!("  {:<12} {}", "image", box_paths.cfs_path.display());
    println!("  {:<12} {}", "rootfs", box_paths.rootfs_path.display());
    println!("  {:<12} {}", "mount", box_paths.mount_path.display());
    println!();

    println!(
        "{} {}",
        style_label("last prepared", colors),
        format_last_built_at(meta.last_built_at.as_deref())
    );

    Ok(())
}

use super::common::describe_source;
use super::ui::{
    colors_enabled, inspect_status, style_recorded_state, style_status_badge, style_title,
};
use crate::config::BoxManifest;
use crate::metadata::BoxMetadata;
use crate::paths::Paths;
use anyhow::Result;

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
        let status = inspect_status(built_live);
        let source = describe_source(&manifest, &box_paths);

        println!(
            "{} {}",
            style_title(&name, colors),
            style_status_badge(status, colors)
        );
        println!("  {:<12} {}", "source", source);
        println!(
            "  {:<12} {}",
            "prepared",
            style_recorded_state(meta.built, built_live, colors)
        );
        if !manifest.shell.tools.is_empty() {
            println!("  {:<12} {}", "tools", manifest.shell.tools.join(", "));
        }
        if !manifest.host.tools.is_empty() {
            println!(
                "  {:<12} {} (host)",
                "tools",
                manifest.host.tools.join(", ")
            );
        }
        println!();
    }

    Ok(())
}

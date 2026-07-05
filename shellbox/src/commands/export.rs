use super::ui::{colors_enabled, style_section, style_title};
use super::wrappers::write_wrapper_script;
use crate::config;
use crate::paths::Paths;
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct ExportRecord {
    pub(super) box_name: String,
}

/// Result of reconciling a box's exports against its declared tools.
pub(super) struct ExportSyncReport {
    /// Tools whose wrappers were written or updated this prepare.
    pub(super) exported: Vec<String>,
    /// Tools this box previously owned but no longer declares; removed.
    pub(super) removed: Vec<String>,
}

/// Reconcile a box's persistent exports with its declared `[shell].tools`.
///
/// This is the single write path for exports, run at the end of every
/// successful `prepare`. The policy is **last-prepare-wins**: every declared
/// tool is (re)written here regardless of who owned it before, and this box is
/// recorded as the owner. Any tool this box currently owns but no longer
/// declares is removed.
pub(super) fn sync_box_exports(
    paths: &Paths,
    box_name: &str,
    tools: &[String],
    env_vars: &[(String, String)],
) -> Result<ExportSyncReport> {
    let mut exported = Vec::new();
    for tool in tools {
        export_one_command(paths, box_name, tool, env_vars)?;
        exported.push(tool.clone());
    }

    let mut removed = Vec::new();
    for (tool, record) in scan_exports(paths)? {
        if record.box_name == box_name && !tools.iter().any(|t| t == &tool) {
            remove_export(paths, &tool)?;
            removed.push(tool);
        }
    }

    Ok(ExportSyncReport { exported, removed })
}

/// Remove every export owned by `box_name`. Returns the tool names removed.
/// Used by `rm` so deleting a box cleans up its exports (declarative symmetry).
pub(super) fn unexport_box(paths: &Paths, box_name: &str) -> Result<Vec<String>> {
    let mut removed = Vec::new();
    for (tool, record) in scan_exports(paths)? {
        if record.box_name == box_name {
            remove_export(paths, &tool)?;
            removed.push(tool);
        }
    }
    Ok(removed)
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

fn export_one_command(
    paths: &Paths,
    box_name: &str,
    cmd: &str,
    env_vars: &[(String, String)],
) -> Result<PathBuf> {
    config::validate_tool_name(cmd)?;

    let target = paths.exports_bin_dir().join(cmd);
    let meta_path = paths.exports_metadata_dir().join(format!("{cmd}.json"));

    // last-prepare-wins: always overwrite, regardless of prior ownership.
    write_wrapper_script(&target, box_name, cmd, env_vars)?;
    save_export_record(
        &meta_path,
        &ExportRecord {
            box_name: box_name.to_string(),
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

pub(super) fn scan_exports(paths: &Paths) -> Result<Vec<(String, ExportRecord)>> {
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

fn remove_export(paths: &Paths, tool: &str) -> Result<()> {
    let target = paths.exports_bin_dir().join(tool);
    let meta_path = paths.exports_metadata_dir().join(format!("{tool}.json"));

    if meta_path.exists() {
        std::fs::remove_file(&meta_path)
            .with_context(|| format!("failed to remove {}", meta_path.display()))?;
    }
    if target.exists() {
        std::fs::remove_file(&target)
            .with_context(|| format!("failed to remove {}", target.display()))?;
    }

    Ok(())
}

use super::common::{normalize_tools, require_manifest};
use super::ui::{colors_enabled, style_action, style_section, style_title};
use super::wrappers::write_wrapper_script;
use crate::cli::{ExportArgs, UnexportArgs};
use crate::config::{self, BoxManifest};
use crate::paths::Paths;
use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct ExportRecord {
    pub(super) box_name: String,
    pub(super) command: String,
}

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

use crate::config::{self, BoxManifest};
use crate::paths::BoxPaths;
use crate::util::run_command;
use anyhow::{Context, Result, bail};
use nix::unistd::Uid;
use std::path::{Path, PathBuf};
use std::process::Command;

/// Load the manifest for a box, with a clear error if the box isn't defined.
pub(super) fn require_manifest(box_paths: &BoxPaths) -> Result<BoxManifest> {
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

pub(super) fn is_mountpoint(path: &Path) -> bool {
    Command::new("mountpoint")
        .arg("-q")
        .arg(path)
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

pub(super) fn remove_tree_force(path: &Path) -> Result<()> {
    if !path.exists() {
        return Ok(());
    }
    run_command(Command::new("bash").arg("-lc").arg(format!(
        "chmod -R u+rwX '{}' 2>/dev/null || true; rm -rf --one-file-system '{}'",
        path.display(),
        path.display()
    )))
}

pub(super) fn require_root(verb: &str) -> Result<()> {
    if Uid::effective().is_root() {
        return Ok(());
    }
    bail!("{} requires root\nrun: sudo shellbox {} <name>", verb, verb);
}

pub(super) fn chown_mount_dir_to_sudo_user(path: &Path) -> Result<()> {
    let uid = std::env::var("SUDO_UID").ok();
    let gid = std::env::var("SUDO_GID").ok();
    if let (Some(uid), Some(gid)) = (uid, gid) {
        let spec = format!("{uid}:{gid}");
        run_command(Command::new("chown").arg(&spec).arg(path))?;
    }
    Ok(())
}

pub(super) fn normalize_tools(tools: Vec<String>) -> Result<Vec<String>> {
    let mut normalized = Vec::new();
    for tool in tools {
        config::validate_tool_name(&tool)?;
        if !normalized.iter().any(|existing: &String| existing == &tool) {
            normalized.push(tool);
        }
    }
    Ok(normalized)
}

pub(super) fn home_dir() -> Result<PathBuf> {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .context("HOME is not set")
}

pub(super) fn default_shell(root: &Path) -> String {
    if root.join("bin/bash").exists() {
        "/bin/bash".to_string()
    } else {
        "/bin/sh".to_string()
    }
}

pub(super) fn describe_source(manifest: &BoxManifest, _box_paths: &BoxPaths) -> String {
    format!("image · {}", manifest.image)
}

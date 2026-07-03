use super::common::{default_shell, normalize_tools, require_manifest};
use super::runtime::{create_shell_session, run_box_command, run_host_shell};
use crate::cli::{NameArgs, RunArgs};
use crate::metadata::BoxMetadata;
use crate::paths::Paths;
use anyhow::{Result, bail};

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

    // If no command is given, open an interactive shell (`/bin/bash` if
    // present, else `/bin/sh`) — this covers the former `enter` command.
    let cmd: Vec<String> = if args.cmd.is_empty() {
        vec![default_shell(&box_paths.mount_path)]
    } else {
        args.cmd
    };
    let status = run_box_command(&box_paths, &paths.store_dir(), &manifest, &cmd)?;
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

fn ensure_runtime_ready(name: &str, box_paths: &crate::paths::BoxPaths, meta: &BoxMetadata) -> Result<()> {
    if !meta.built || !box_paths.cfs_path.exists() {
        bail!("box '{}' is not prepared", name);
    }
    // Note: a box does NOT need to be (kernel-)mounted to run. If it is mounted,
    // `run`/`shell` use that fast path; otherwise they fall back to the
    // fully rootless FUSE runtime. So we no longer require `mount` here.
    Ok(())
}

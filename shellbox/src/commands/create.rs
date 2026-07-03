use super::common::{is_mountpoint, normalize_tools, remove_tree_force};
use super::ui::{colors_enabled, style_action, style_title};
use crate::cli::CreateArgs;
use crate::config::{self, BoxManifest, ShellConfig};
use crate::metadata::BoxMetadata;
use crate::paths::Paths;
use crate::util::run_command;
use anyhow::{Context, Result, bail};
use std::path::{Path, PathBuf};
use std::process::Command;

struct Import {
    manifest: Option<BoxManifest>,
    /// Directory whose contents should be copied wholesale into the box dir.
    /// Only set for an explicit `--from <dir>`.
    extras_dir: Option<PathBuf>,
}

pub fn cmd_create(args: CreateArgs) -> Result<()> {
    let paths = Paths::new()?;
    paths.ensure_base_dirs()?;

    // Resolve the import source.
    let import = match &args.from {
        Some(p) => import_from_explicit(Path::new(p))?,
        None => import_from_cwd_auto()?,
    };

    // name: CLI > manifest 'name' > --from dir name.
    let name = args
        .name
        .clone()
        .or_else(|| import.manifest.as_ref().and_then(|m| m.name.clone()))
        .or_else(|| {
            if let Some(p) = &args.from {
                let pb = PathBuf::from(p);
                if pb.is_dir() {
                    return pb.file_name().and_then(|n| n.to_str()).map(String::from);
                }
            }
            None
        })
        .context(
            "box name is required\nprovide --name, a 'name' field in the manifest, or name the --from directory",
        )?;
    config::validate_name(&name)?;

    let box_paths = paths.box_paths(&name);

    // source: CLI --image overrides the import; otherwise the manifest's
    // `image` is used. `image` is required.
    let image = args
        .image
        .clone()
        .or_else(|| import.manifest.as_ref().map(|m| m.image.clone()))
        .context(
            "image is required\nprovide --image or set 'image' in the manifest",
        )?;

    // tools: CLI appends to manifest.
    let mut tools = import
        .manifest
        .as_ref()
        .map(|m| m.shell.tools.clone())
        .unwrap_or_default();
    tools.extend(args.tools);
    let tools = normalize_tools(tools)?;

    let env = import
        .manifest
        .as_ref()
        .map(|m| m.shell.env.clone())
        .unwrap_or_default();

    // Materialize the box directory.
    if box_paths.dir.exists() {
        if !args.force {
            bail!("box '{}' already exists; use --force to overwrite", name);
        }
        if is_mountpoint(&box_paths.mount_path) {
            bail!("box '{}' is mounted; unmount it before overwriting", name);
        }
        remove_tree_force(&box_paths.dir)?;
    }
    std::fs::create_dir_all(&box_paths.dir)
        .with_context(|| format!("failed to create {}", box_paths.dir.display()))?;

    // Copy companion files from an explicit --from <dir>.
    if let Some(extras) = &import.extras_dir {
        copy_dir_contents(extras, &box_paths.dir)?;
    }

    // Write the canonical manifest.
    let manifest = BoxManifest {
        name: Some(name.clone()),
        image,
        shell: ShellConfig { tools, env },
        host: config::HostConfig::default(),
    };
    manifest.save(&box_paths.manifest_path)?;

    // Fresh derived-state metadata.
    std::fs::create_dir_all(&box_paths.state_dir)
        .with_context(|| format!("failed to create {}", box_paths.state_dir.display()))?;
    BoxMetadata::default().save(&box_paths.metadata_path)?;

    let colors = colors_enabled();
    println!("{} {}", style_action("created", colors), style_title(&name, colors));
    println!("  {:<12} {}", "manifest", box_paths.manifest_path.display());
    println!("  {:<12} {}", "source", format!("image · {}", manifest.image));
    println!("  {:<12} {}", "state", box_paths.state_dir.display());
    if !manifest.shell.tools.is_empty() {
        println!("  {:<12} {}", "tools", manifest.shell.tools.join(", "));
    }
    Ok(())
}

fn import_from_explicit(from_path: &Path) -> Result<Import> {
    if from_path.is_file() {
        let manifest = BoxManifest::load_from(from_path)?;
        return Ok(Import {
            manifest: Some(manifest),
            extras_dir: None,
        });
    }
    if from_path.is_dir() {
        let manifest_path = from_path.join("shellbox.toml");
        let manifest = if manifest_path.is_file() {
            Some(BoxManifest::load_from(&manifest_path)?)
        } else {
            None
        };
        Ok(Import {
            manifest,
            extras_dir: Some(from_path.to_path_buf()),
        })
    } else {
        bail!("--from path does not exist: {}", from_path.display());
    }
}

/// Auto-discover `./shellbox.toml` (old behavior). No companion files.
fn import_from_cwd_auto() -> Result<Import> {
    let cwd = std::env::current_dir().context("failed to get current directory")?;
    let manifest_path = cwd.join("shellbox.toml");
    let manifest = if manifest_path.is_file() {
        Some(BoxManifest::load_from(&manifest_path)?)
    } else {
        None
    };
    Ok(Import {
        manifest,
        extras_dir: None,
    })
}

fn copy_dir_contents(src: &Path, dst: &Path) -> Result<()> {
    // `cp -a src/. dst/` copies directory contents (including dotfiles) into dst.
    run_command(
        Command::new("cp")
            .arg("-a")
            .arg(format!("{}/.", src.display()))
            .arg(dst),
    )
}

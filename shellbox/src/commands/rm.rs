use super::common::remove_tree_force;
use super::export::unexport_box;
use super::ui::{colors_enabled, style_action, style_title};
use crate::cli::RmArgs;
use crate::paths::Paths;
use anyhow::{Context, Result, bail};

pub fn cmd_rm(args: RmArgs) -> Result<()> {
    let paths = Paths::new()?;
    let box_paths = paths.box_paths(&args.name);

    let manifest_exists = box_paths.manifest_path.exists();
    let state_exists = box_paths.state_dir.exists();

    if !manifest_exists && !state_exists {
        let colors = colors_enabled();
        println!(
            "{} {}",
            style_action("removed", colors),
            style_title(&args.name, colors)
        );
        println!("  {:<12} already absent", "status");
        return Ok(());
    }

    // Derived artifacts always go.
    if state_exists {
        remove_tree_force(&box_paths.state_dir)?;
    }

    let colors = colors_enabled();

    if args.purge && manifest_exists {
        // Removing a symlinked manifest dir: only the symlink should go, not
        // the target's contents. `rm -rf` on a symlink path unlinks it, but be
        // explicit so we never traverse into the real directory.
        let symlink_meta = std::fs::symlink_metadata(&box_paths.dir);
        let is_symlink = symlink_meta
            .as_ref()
            .map(|m| m.file_type().is_symlink())
            .unwrap_or(false);
        if is_symlink && !args.force {
            bail!(
                "box '{}' is a symlink; pass --force to remove the symlink (the target is left untouched)",
                args.name
            );
        }
        if is_symlink {
            std::fs::remove_file(&box_paths.dir)
                .with_context(|| format!("failed to remove symlink {}", box_paths.dir.display()))?;
        } else {
            remove_tree_force(&box_paths.dir)?;
        }
    }

    println!(
        "{} {}",
        style_action("removed", colors),
        style_title(&args.name, colors)
    );
    if state_exists {
        println!("  {:<12} {}", "state", box_paths.state_dir.display());
    }
    if args.purge && manifest_exists {
        println!("  {:<12} {}", "manifest", box_paths.dir.display());
    }
    if !args.purge && manifest_exists {
        println!("  {:<12} manifest at {}", "kept", box_paths.dir.display());
    }

    // Clean up any exports this box still owns (declarative symmetry with
    // prepare's sync: deleting a box reclaims its tool wrappers).
    let unexported = unexport_box(&paths, &args.name)?;
    if !unexported.is_empty() {
        println!("  {:<12} {}", "unexported", unexported.join(", "));
    }
    Ok(())
}

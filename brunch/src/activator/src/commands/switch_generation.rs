use crate::{state_dir, symlink_atomic, commands::apply::{link_desktop_assets, link_files, cleanup_files}};
use anyhow::{Context, Result};

pub fn run(gen_num: u32) -> Result<()> {
    let state = state_dir()?;
    let generations = state.join("generations");
    let gen_path = generations.join(gen_num.to_string());

    if !gen_path.exists() {
        anyhow::bail!("Generation {} does not exist", gen_num);
    }

    let current = state.join("current");

    let old_current = if current.exists() {
        std::fs::read_link(&current).ok()
    } else {
        None
    };

    log::debug!("Updating current symlink to generation {}", gen_num);

    symlink_atomic(&gen_path, &current).context("Failed to update current symlink")?;

    log::info!("Switched to generation {}", gen_num);

    link_desktop_assets(&current).context("Failed to link desktop assets for generation switch")?;
    link_files(&current).context("Failed to link home files for generation switch")?;

    if let Some(old_path) = old_current {
        cleanup_files(&old_path, &gen_path).context("Failed to cleanup old files")?;
    }

    println!("Switched to generation {}", gen_num);
    Ok(())
}

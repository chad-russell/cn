use crate::{
    commands::apply::{
        cleanup_files, cleanup_systemd, link_desktop_assets, link_files, link_systemd,
        prompt_for_elevation, ElevatedOps,
    },
    state_dir, symlink_atomic,
};
use anyhow::{Context, Result};

pub fn run(gen_num: u32) -> Result<()> {
    let state = state_dir()?;
    let generations = state.join("generations");
    let gen_path = generations.join(gen_num.to_string());

    if !gen_path.exists() {
        anyhow::bail!("Generation {} does not exist", gen_num);
    }

    let has_system_units = gen_path.join("systemd/system").exists();
    let has_system_files = gen_path.join("files/root").exists();
    let elevated = if has_system_units || has_system_files {
        prompt_for_elevation()?
    } else {
        false
    };

    let current = state.join("current");

    let old_current = if current.exists() {
        std::fs::read_link(&current).ok()
    } else {
        None
    };

    log::debug!("Updating current symlink to generation {}", gen_num);

    symlink_atomic(&gen_path, &current).context("Failed to update current symlink")?;

    log::info!("Switched to generation {}", gen_num);

    let mut ops = ElevatedOps::new();

    if let Some(ref old_path) = old_current {
        cleanup_systemd(old_path, &gen_path, elevated, &mut ops)
            .context("Failed to cleanup old systemd units")?;
    }

    link_systemd(&current, elevated, &mut ops).context("Failed to link systemd units")?;

    link_desktop_assets(&current).context("Failed to link desktop assets for generation switch")?;
    link_files(&current, elevated, &mut ops).context("Failed to link files for generation switch")?;

    if let Some(ref old_path) = old_current {
        cleanup_files(old_path, &gen_path, elevated, &mut ops)
            .context("Failed to cleanup old files")?;
    }

    if elevated {
        ops.execute()?;
    }

    println!("Switched to generation {}", gen_num);
    Ok(())
}

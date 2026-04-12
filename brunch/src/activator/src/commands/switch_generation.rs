use crate::{
    commands::apply::{
        cleanup_files, cleanup_systemd, link_desktop_assets, link_files, link_systemd,
    },
    state_dir, symlink_atomic,
};
use anyhow::{Context, Result};
use std::io::{self, Write};

pub fn run(gen_num: u32) -> Result<()> {
    let state = state_dir()?;
    let generations = state.join("generations");
    let gen_path = generations.join(gen_num.to_string());

    if !gen_path.exists() {
        anyhow::bail!("Generation {} does not exist", gen_num);
    }

    let has_system_units = gen_path.join("systemd/system").exists();
    let elevated = if has_system_units {
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

    if let Some(ref old_path) = old_current {
        cleanup_systemd(old_path, &gen_path, elevated)
            .context("Failed to cleanup old systemd units")?;
    }

    link_systemd(&current, elevated).context("Failed to link systemd units")?;

    link_desktop_assets(&current).context("Failed to link desktop assets for generation switch")?;
    link_files(&current).context("Failed to link home files for generation switch")?;

    if let Some(ref old_path) = old_current {
        cleanup_files(old_path, &gen_path).context("Failed to cleanup old files")?;
    }

    println!("Switched to generation {}", gen_num);
    Ok(())
}

fn prompt_for_elevation() -> Result<bool> {
    println!("System-level systemd units detected.");
    print!("Apply with elevated privileges? [y/N]: ");
    io::stdout().flush()?;

    let mut input = String::new();
    io::stdin().read_line(&mut input)?;

    Ok(input.trim().to_lowercase() == "y")
}

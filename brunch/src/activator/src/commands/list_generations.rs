use crate::{current_generation, state_dir};
use anyhow::{Context, Result};

pub fn run() -> Result<()> {
    let state = state_dir()?;
    let generations = state.join("generations");

    if !generations.exists() {
        println!("No generations found.");
        return Ok(());
    }

    let current_gen = current_generation(&state)?;
    let mut gens: Vec<u32> = Vec::new();

    for entry in std::fs::read_dir(&generations).context("Failed to read generations")? {
        let entry = entry.context("Failed to read directory entry")?;
        let path = entry.path();
        let filename = path
            .file_name()
            .context("Path has no filename")?
            .to_str()
            .context("Filename not valid UTF-8")?;

        if let Ok(num) = filename.parse::<u32>() {
            gens.push(num);
        }
    }

    gens.sort_unstable();

    println!("Brunch generations:");
    for gen in &gens {
        let marker = if Some(*gen) == current_gen { " (current)" } else { "" };
        println!("  Generation {}{}", gen, marker);
    }

    Ok(())
}

use crate::{current_generation, list_generation_numbers, state_dir};
use anyhow::{anyhow, bail, Context, Result};
use std::collections::BTreeSet;

pub fn run(specs: &[String], dry_run: bool) -> Result<()> {
    if specs.is_empty() {
        bail!("At least one generation spec is required");
    }

    let state = state_dir()?;
    let generations_dir = state.join("generations");

    if !generations_dir.exists() {
        println!("No generations found.");
        return Ok(());
    }

    let existing = list_generation_numbers(&generations_dir)?;
    if existing.is_empty() {
        println!("No generations found.");
        return Ok(());
    }

    let existing_set: BTreeSet<u32> = existing.iter().copied().collect();
    let current = current_generation(&state)?;
    let requested = parse_specs(specs)?;

    let mut to_remove: Vec<u32> = requested
        .into_iter()
        .filter(|gen| existing_set.contains(gen))
        .collect();

    if let Some(current_gen) = current {
        if to_remove.contains(&current_gen) {
            bail!(
                "Refusing to prune current generation {}. Switch generations first.",
                current_gen
            );
        }
    }

    if to_remove.is_empty() {
        println!("No matching generations to prune.");
        return Ok(());
    }

    to_remove.sort_unstable();

    if dry_run {
        println!("Would remove generations:");
        for gen in &to_remove {
            println!("  Generation {}", gen);
        }
        return Ok(());
    }

    for gen in &to_remove {
        let path = generations_dir.join(gen.to_string());
        std::fs::remove_dir_all(&path).context(format!("Failed to remove generation {}", gen))?;
        println!("Removed generation {}", gen);
    }

    Ok(())
}

fn parse_specs(specs: &[String]) -> Result<Vec<u32>> {
    let mut gens = BTreeSet::new();

    for spec in specs {
        for part in spec.split(',') {
            let part = part.trim();
            if part.is_empty() {
                continue;
            }

            if let Some((start, end)) = part.split_once('-') {
                let start = parse_generation(start)?;
                let end = parse_generation(end)?;

                if start > end {
                    bail!(
                        "Invalid generation range '{}': start is greater than end",
                        part
                    );
                }

                for gen in start..=end {
                    gens.insert(gen);
                }
            } else {
                gens.insert(parse_generation(part)?);
            }
        }
    }

    Ok(gens.into_iter().collect())
}

fn parse_generation(value: &str) -> Result<u32> {
    let gen = value
        .parse::<u32>()
        .map_err(|_| anyhow!("Invalid generation '{}'", value))?;

    if gen == 0 {
        bail!("Generation numbers must be positive");
    }

    Ok(gen)
}

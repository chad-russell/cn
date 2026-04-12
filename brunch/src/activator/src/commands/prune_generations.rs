use crate::{current_generation, list_generation_numbers, state_dir};
use anyhow::{anyhow, bail, Context, Result};
use std::collections::BTreeSet;
use std::time::{Duration, SystemTime};

pub fn run(
    specs: &[String],
    dry_run: bool,
    keep_last: Option<usize>,
    all_but_current: bool,
    older_than: Option<&str>,
) -> Result<()> {
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
    let requested = resolve_requested_generations(
        specs,
        keep_last,
        all_but_current,
        older_than,
        &existing,
        &generations_dir,
        current,
    )?;

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

fn resolve_requested_generations(
    specs: &[String],
    keep_last: Option<usize>,
    all_but_current: bool,
    older_than: Option<&str>,
    existing: &[u32],
    generations_dir: &std::path::Path,
    current: Option<u32>,
) -> Result<Vec<u32>> {
    let mut mode_count = 0;
    if !specs.is_empty() {
        mode_count += 1;
    }
    if keep_last.is_some() {
        mode_count += 1;
    }
    if all_but_current {
        mode_count += 1;
    }
    if older_than.is_some() {
        mode_count += 1;
    }

    if mode_count == 0 {
        bail!("Provide generation specs or one of --keep-last, --all-but-current, --older-than");
    }

    if mode_count > 1 {
        bail!("Use only one prune mode at a time");
    }

    if let Some(count) = keep_last {
        return Ok(resolve_keep_last(existing, count));
    }

    if all_but_current {
        return Ok(existing
            .iter()
            .copied()
            .filter(|gen| Some(*gen) != current)
            .collect());
    }

    if let Some(age) = older_than {
        return Ok(resolve_older_than(existing, generations_dir, age)?
            .into_iter()
            .filter(|gen| Some(*gen) != current)
            .collect());
    }

    parse_specs(specs)
}

fn resolve_keep_last(existing: &[u32], count: usize) -> Vec<u32> {
    if count >= existing.len() {
        return Vec::new();
    }

    existing[..existing.len() - count].to_vec()
}

fn resolve_older_than(
    existing: &[u32],
    generations_dir: &std::path::Path,
    age: &str,
) -> Result<Vec<u32>> {
    let threshold = parse_age(age)?;
    let now = SystemTime::now();
    let mut result = Vec::new();

    for gen in existing {
        let path = generations_dir.join(gen.to_string());
        let metadata = std::fs::metadata(&path)
            .context(format!("Failed to read generation metadata for {}", gen))?;
        let modified = metadata
            .modified()
            .context(format!("Failed to read generation mtime for {}", gen))?;

        let age = now.duration_since(modified).unwrap_or(Duration::ZERO);
        if age > threshold {
            result.push(*gen);
        }
    }

    Ok(result)
}

fn parse_age(value: &str) -> Result<Duration> {
    if value.len() < 2 {
        bail!(
            "Invalid age '{}': expected formats like 30d, 12h, 2w",
            value
        );
    }

    let (number_part, unit_part) = value.split_at(value.len() - 1);
    let amount = number_part
        .parse::<u64>()
        .map_err(|_| anyhow!("Invalid age '{}'", value))?;

    if amount == 0 {
        bail!("Age must be greater than zero");
    }

    let seconds = match unit_part {
        "h" => amount.checked_mul(60 * 60),
        "d" => amount.checked_mul(60 * 60 * 24),
        "w" => amount.checked_mul(60 * 60 * 24 * 7),
        _ => bail!("Invalid age unit '{}': use h, d, or w", unit_part),
    }
    .ok_or_else(|| anyhow!("Age '{}' is too large", value))?;

    Ok(Duration::from_secs(seconds))
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

use crate::{current_generation, list_generation_numbers, state_dir};
use anyhow::Result;

pub fn run() -> Result<()> {
    let state = state_dir()?;
    let generations = state.join("generations");

    if !generations.exists() {
        println!("No generations found.");
        return Ok(());
    }

    let current_gen = current_generation(&state)?;
    let gens = list_generation_numbers(&generations)?;

    println!("Brunch generations:");
    for gen in &gens {
        let marker = if Some(*gen) == current_gen {
            " (current)"
        } else {
            ""
        };
        println!("  Generation {}{}", gen, marker);
    }

    Ok(())
}

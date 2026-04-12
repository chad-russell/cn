use anyhow::{anyhow, Context, Result};
use clap::{Parser, Subcommand};
use dirs;
use std::path::{Path, PathBuf};

mod commands;

fn main() -> Result<()> {
    env_logger::init();
    let cli = Cli::parse();
    match cli.command {
        Commands::Apply {
            project_path,
            target,
        } => commands::apply::run(&project_path, target.as_deref()),
        Commands::ListGenerations => commands::list_generations::run(),
        Commands::PruneGenerations {
            specs,
            dry_run,
            keep_last,
            all_but_current,
            older_than,
        } => commands::prune_generations::run(
            &specs,
            dry_run,
            keep_last,
            all_but_current,
            older_than.as_deref(),
        ),
        Commands::SwitchGeneration { gen_num } => commands::switch_generation::run(gen_num),
    }
}

#[derive(Parser)]
#[command(name = "brunch")]
#[command(about = "Brunch - Declarative home manager for Brioche", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    #[command(about = "Build and apply a Brioche project as a new generation")]
    Apply {
        #[arg(
            value_name = "PROJECT_PATH",
            help = "Path to Brioche project directory"
        )]
        project_path: PathBuf,
        #[arg(
            long,
            value_name = "TARGET",
            help = "Optional named build target, for example 'hub'"
        )]
        target: Option<String>,
    },
    #[command(about = "List all generations and mark the current one")]
    ListGenerations,
    #[command(about = "Remove specific generations or generation ranges")]
    PruneGenerations {
        #[arg(
            value_name = "GEN_SPEC",
            help = "Generation numbers or ranges, e.g. 3 5-8 10,12"
        )]
        specs: Vec<String>,
        #[arg(
            long,
            help = "Show which generations would be removed without deleting them"
        )]
        dry_run: bool,
        #[arg(long, value_name = "COUNT", help = "Keep the newest COUNT generations")]
        keep_last: Option<usize>,
        #[arg(long, help = "Remove all generations except the current one")]
        all_but_current: bool,
        #[arg(
            long,
            value_name = "AGE",
            help = "Remove generations older than AGE (e.g. 30d, 12h, 2w)"
        )]
        older_than: Option<String>,
    },
    #[command(about = "Switch to a specific generation")]
    SwitchGeneration {
        #[arg(value_name = "GEN_NUM", help = "Generation number to switch to")]
        gen_num: u32,
    },
}

/// Get the Brunch state directory following XDG Base Directory spec
pub fn state_dir() -> Result<PathBuf> {
    let base = dirs::state_dir().ok_or_else(|| anyhow!("Failed to resolve state directory"))?;
    Ok(base.join("brunch"))
}

/// Get the next generation number
///
/// Scans the generations directory and returns the next sequential number
pub fn next_generation(generations_dir: &Path) -> Result<u32> {
    if !generations_dir.exists() {
        return Ok(1);
    }

    let mut max_gen = 0u32;
    for entry in
        std::fs::read_dir(generations_dir).context("Failed to read generations directory")?
    {
        let entry = entry.context("Failed to read directory entry")?;
        let path = entry.path();
        let filename = path
            .file_name()
            .context("Path has no filename")?
            .to_str()
            .context("Filename not valid UTF-8")?;

        if let Ok(num) = filename.parse::<u32>() {
            if num > max_gen {
                max_gen = num;
            }
        }
    }

    Ok(max_gen + 1)
}

/// Create an atomic symlink update
///
/// Creates a temporary symlink then atomically renames it over the target.
/// This ensures the symlink always exists during the update.
pub fn symlink_atomic(target: &Path, link: &Path) -> Result<()> {
    let parent = link.parent().context("Link path has no parent directory")?;

    std::fs::create_dir_all(parent).context("Failed to create parent directory")?;

    if let Ok(current_target) = std::fs::read_link(link) {
        if current_target == target {
            return Ok(());
        }
    }

    if link.exists() {
        let metadata = std::fs::symlink_metadata(link).context("Failed to get link metadata")?;

        if !metadata.file_type().is_symlink() {
            let timestamp = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)?
                .as_secs();
            let backup_path = format!("{}.bak-{}", link.display(), timestamp);
            std::fs::rename(link, backup_path).context("Failed to backup existing file")?;
        }
    }

    let temp_link = format!("{}.tmp", link.display());
    std::os::unix::fs::symlink(target, &temp_link).context("Failed to create temporary symlink")?;

    std::fs::rename(&temp_link, link).context("Failed to atomically update symlink")?;

    Ok(())
}

/// Get the current generation number
///
/// Reads the "current" symlink and extracts the generation number
pub fn current_generation(state_dir: &Path) -> Result<Option<u32>> {
    let current_link = state_dir.join("current");

    if !current_link.exists() {
        return Ok(None);
    }

    let target = std::fs::read_link(&current_link).context("Failed to read current symlink")?;

    let gen_str = target.file_name().and_then(|n| n.to_str()).unwrap_or("");

    let gen = gen_str.parse::<u32>().ok();
    Ok(gen)
}

pub fn list_generation_numbers(generations_dir: &Path) -> Result<Vec<u32>> {
    if !generations_dir.exists() {
        return Ok(Vec::new());
    }

    let mut gens = Vec::new();
    for entry in
        std::fs::read_dir(generations_dir).context("Failed to read generations directory")?
    {
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
    Ok(gens)
}

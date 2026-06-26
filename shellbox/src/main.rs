mod app;
mod cli;
mod config;
mod metadata;
mod paths;
mod util;

use anyhow::Result;
use clap::Parser;
use cli::{Cli, Command};

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Command::Create(args) => app::cmd_create(args)?,
        Command::Link(args) => app::cmd_link(args)?,
        Command::Build(args) => app::cmd_build(args)?,
        Command::List => app::cmd_list()?,
        Command::Inspect(args) => app::cmd_inspect(args)?,
        Command::Mount(args) => app::cmd_mount(args)?,
        Command::Unmount(args) => app::cmd_unmount(args)?,
        Command::Run(args) => app::cmd_run(args)?,
        Command::Shell(args) => app::cmd_shell(args)?,
        Command::Enter(args) => app::cmd_enter(args)?,
        Command::Rm(args) => app::cmd_rm(args)?,
        Command::Rename(args) => app::cmd_rename(args)?,
        Command::Export(args) => app::cmd_export(args)?,
        Command::Unexport(args) => app::cmd_unexport(args)?,
        Command::ListExports => app::cmd_list_exports()?,
        Command::Migrate => app::cmd_migrate()?,
    }

    Ok(())
}

mod cli;
mod commands;
mod config;
mod fuse;
mod host_exec;
mod metadata;
mod paths;
mod util;

use anyhow::Result;
use clap::Parser;
use cli::{Cli, Command};

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Command::Create(args) => commands::cmd_create(args)?,
        Command::Link(args) => commands::cmd_link(args)?,
        Command::Prepare(args) => commands::cmd_prepare(args)?,
        Command::List => commands::cmd_list()?,
        Command::Inspect(args) => commands::cmd_inspect(args)?,
        Command::Mount(args) => commands::cmd_mount(args)?,
        Command::Unmount(args) => commands::cmd_unmount(args)?,
        Command::Run(args) => commands::cmd_run(args)?,
        Command::Shell(args) => commands::cmd_shell(args)?,
        Command::Rm(args) => commands::cmd_rm(args)?,
        Command::Export(args) => commands::cmd_export(args)?,
        Command::Unexport(args) => commands::cmd_unexport(args)?,
        Command::ListExports => commands::cmd_list_exports()?,
    }

    Ok(())
}

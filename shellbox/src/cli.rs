use clap::{Args, Parser, Subcommand};

#[derive(Parser, Debug)]
#[command(name = "shellbox", version, about = "composefs-backed devshell utility")]
pub struct Cli {
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Subcommand, Debug)]
pub enum Command {
    Create(CreateArgs),
    Link(LinkArgs),
    Prepare(NameArgs),
    List,
    Inspect(NameArgs),
    Mount(NameArgs),
    Unmount(NameArgs),
    Run(RunArgs),
    Shell(NameArgs),
    Rm(RmArgs),
    Export(ExportArgs),
    Unexport(UnexportArgs),
    ListExports,
}

#[derive(Args, Debug)]
pub struct LinkArgs {
    /// Source directory to symlink into `boxes/`. Defaults to the current
    /// directory — so `cd <box-dir> && shellbox link` just works.
    pub source: Option<String>,

    /// Override the box name (otherwise derived from the source dir name).
    #[arg(long)]
    pub name: Option<String>,

    /// Overwrite an existing box. Refuses if the box is mounted.
    #[arg(long)]
    pub force: bool,
}

#[derive(Args, Debug)]
pub struct NameArgs {
    pub name: String,
}

#[derive(Args, Debug)]
pub struct CreateArgs {
    #[arg(long)]
    pub name: Option<String>,

    /// OCI image reference the box is materialized from. Overrides an `image`
    /// field brought in by `--from`.
    #[arg(long)]
    pub image: Option<String>,

    #[arg(long = "tool")]
    pub tools: Vec<String>,

    /// Import the box from an external manifest file or directory (e.g. a
    /// dotfiles-managed box). If omitted, defaults to the current directory.
    #[arg(long = "from")]
    pub from: Option<String>,

    /// Overwrite an existing box. Refuses if the box is mounted.
    #[arg(long)]
    pub force: bool,
}

#[derive(Args, Debug)]
pub struct RunArgs {
    pub name: String,

    /// Command to run inside the box (after `--`). If omitted, opens an
    /// interactive shell (`/bin/bash` if present, else `/bin/sh`).
    #[arg(last = true)]
    pub cmd: Vec<String>,
}

#[derive(Args, Debug)]
pub struct ExportArgs {
    pub name: String,
    pub cmd: Option<String>,

    #[arg(long)]
    pub all: bool,

    #[arg(long)]
    pub force: bool,
}

#[derive(Args, Debug)]
pub struct UnexportArgs {
    pub tool: Option<String>,

    #[arg(long)]
    pub all: bool,

    #[arg(long = "box")]
    pub box_name: Option<String>,
}

#[derive(Args, Debug)]
pub struct RmArgs {
    pub name: String,

    /// Also remove the authored manifest directory (`boxes/<name>/`).
    #[arg(long)]
    pub purge: bool,

    /// Required to purge a box whose manifest directory is a symlink, as an
    /// extra confirmation.
    #[arg(long)]
    pub force: bool,
}

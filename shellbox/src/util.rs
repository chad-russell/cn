use anyhow::{Context, Result, bail};
use std::process::{Command, ExitStatus, Stdio};

pub fn run_command(cmd: &mut Command) -> Result<()> {
    let display = format!("{:?}", cmd);
    let output = cmd
        .output()
        .with_context(|| format!("failed to start {display}"))?;

    if output.status.success() {
        return Ok(());
    }

    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();

    if !stderr.is_empty() {
        bail!("command failed: {display}\n{stderr}");
    }
    if !stdout.is_empty() {
        bail!("command failed: {display}\n{stdout}");
    }
    bail!("command failed: {display}");
}

pub fn command_output(cmd: &mut Command) -> Result<String> {
    let display = format!("{:?}", cmd);
    let output = cmd
        .output()
        .with_context(|| format!("failed to start {display}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        if !stderr.is_empty() {
            bail!("command failed: {display}\n{stderr}");
        }
        bail!("command failed: {display}");
    }

    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

pub fn run_command_inherit(cmd: &mut Command) -> Result<ExitStatus> {
    let display = format!("{:?}", cmd);
    let status = cmd
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .with_context(|| format!("failed to start {display}"))?;
    Ok(status)
}

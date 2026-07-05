use anyhow::{Context, Result};
use std::ffi::OsString;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

pub(super) fn write_wrapper_script(
    target: &Path,
    box_name: &str,
    cmd: &str,
    env_vars: &[(String, String)],
) -> Result<()> {
    let shellbox = current_shellbox_invocation();
    let mut lines = String::from("#!/usr/bin/env bash\n");
    // Values are author-supplied literals (no expansion); inline them so
    // wrappers work outside any box shell session.
    for (k, v) in env_vars {
        lines.push_str(&format!("export {}={}\n", k, shell_quote(v)));
    }
    lines.push_str(&format!(
        "exec {} run {} -- {} \"$@\"\n",
        shell_quote(&shellbox),
        shell_quote(box_name),
        shell_quote(cmd),
    ));

    std::fs::write(target, lines)
        .with_context(|| format!("failed to write {}", target.display()))?;
    let mut perms = std::fs::metadata(target)?.permissions();
    perms.set_mode(0o755);
    std::fs::set_permissions(target, perms)?;
    Ok(())
}

pub(super) fn current_shellbox_invocation() -> OsString {
    std::env::current_exe()
        .ok()
        .map(|p| p.into_os_string())
        .unwrap_or_else(|| OsString::from("shellbox"))
}

pub(super) fn shell_quote(s: impl AsRef<std::ffi::OsStr>) -> String {
    let s = s.as_ref().to_string_lossy();
    format!("'{}'", s.replace('\'', "'\"'\"'"))
}

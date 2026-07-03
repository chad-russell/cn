use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::Path;

/// A box definition.
///
/// This is the single source of truth for a box. It lives in place at
/// `boxes/<name>/shellbox.toml` and is read on demand by every command that
/// needs it. There is no separate "stored" form and no snapshot step: editing
/// the file is immediately effective.
///
/// A box is always image-backed: `image` is the OCI image reference the box is
/// materialized from.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct BoxManifest {
    /// Optional box name. If present it must match the box directory name.
    #[serde(default)]
    pub name: Option<String>,

    /// OCI image reference the box is materialized from. Required.
    pub image: String,

    #[serde(default)]
    pub shell: ShellConfig,

    /// Host-executed tools. Declared here but resolved differently from
    /// `[shell].tools`: these names are surfaced inside a box runtime
    /// (`run`) as shims that forward execution to the **host** via the
    /// user's systemd manager (`systemd-run --user`). They let a box transparently
    /// use host-only tools (e.g. `podman`) that cannot live inside the read-only
    /// box rootfs.
    ///
    /// In `shell`/`export` (host-side) modes these are a no-op: the real tool is
    /// already on the host PATH, so no shim is needed.
    #[serde(default)]
    pub host: HostConfig,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct HostConfig {
    #[serde(default)]
    pub tools: Vec<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ShellConfig {
    #[serde(default)]
    pub tools: Vec<String>,

    /// Environment variables to set whenever the box is used. Values are
    /// applied **verbatim** — there is no token expansion. If a box wants to
    /// point an env var at an absolute path on disk, the author writes the
    /// absolute path.
    #[serde(default)]
    pub env: BTreeMap<String, String>,
}

impl BoxManifest {
    /// Parse a manifest from a TOML file.
    pub fn load_from(path: &Path) -> Result<Self> {
        let data = std::fs::read(path)
            .with_context(|| format!("failed to read manifest {}", path.display()))?;
        toml::from_str(&String::from_utf8_lossy(&data))
            .with_context(|| format!("failed to parse manifest {}", path.display()))
    }

    /// Serialize this manifest to a TOML file at `path`.
    pub fn save(&self, path: &Path) -> Result<()> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .with_context(|| format!("failed to create {}", parent.display()))?;
        }
        let data = toml::to_string_pretty(self)
            .context("failed to serialize manifest")?;
        std::fs::write(path, data)
            .with_context(|| format!("failed to write {}", path.display()))?;
        Ok(())
    }

    /// Declared env vars as a sorted `(key, value)` list, verbatim.
    pub fn shell_env(&self) -> Vec<(String, String)> {
        self.shell
            .env
            .iter()
            .map(|(k, v)| (k.clone(), v.clone()))
            .collect()
    }

    /// Declared host-exec tools, verbatim. Validation/dedup is the caller's job
    /// (mirrors how `shell.tools` is consumed via `normalize_tools`).
    pub fn host_tools(&self) -> Vec<String> {
        self.host.tools.clone()
    }
}

/// A box name may only contain ascii letters, digits, `-` and `_`. This matches
/// the set of characters that are safe in a directory name everywhere we care
/// about, which matters because the name *is* the directory name.
pub fn validate_name(name: &str) -> Result<()> {
    if name.is_empty() {
        bail!("box name cannot be empty");
    }
    if !name
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
    {
        bail!("box name must contain only ascii letters, digits, '-' or '_'");
    }
    Ok(())
}

pub fn validate_tool_name(name: &str) -> Result<()> {
    if name.is_empty() {
        bail!("tool name cannot be empty");
    }
    if name.chars().any(|c| c.is_whitespace() || c == '/' || c == '\0') {
        bail!("tool name must not contain whitespace or '/'");
    }
    Ok(())
}

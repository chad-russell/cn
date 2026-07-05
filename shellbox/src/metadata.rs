use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

/// Derived prepare state for a box.
///
/// This is a **display hint, not authoritative.** Commands re-check live state
/// (e.g. `cfs_path.exists()`) before deciding anything — `built` and
/// `last_built_at` only feed `list`/`inspect` output and a quick "is it worth
/// even checking further" fast path. Paths are not stored here: they are always
/// derivable from the box name via `Paths::box_paths`.
///
/// The field name `built` is kept for on-disk stability of `metadata.json`;
/// user-facing strings say "prepared".
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct BoxMetadata {
    #[serde(default)]
    pub built: bool,
    #[serde(default)]
    pub last_built_at: Option<String>,
}

impl BoxMetadata {
    pub fn save(&self, path: &Path) -> Result<()> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .with_context(|| format!("failed to create {}", parent.display()))?;
        }
        let data = serde_json::to_vec_pretty(self)?;
        std::fs::write(path, data)
            .with_context(|| format!("failed to write {}", path.display()))?;
        Ok(())
    }

    pub fn load(path: &Path) -> Result<Self> {
        let data =
            std::fs::read(path).with_context(|| format!("failed to read {}", path.display()))?;
        let meta = serde_json::from_slice(&data)
            .with_context(|| format!("failed to parse {}", path.display()))?;
        Ok(meta)
    }
}

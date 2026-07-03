use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

/// Derived prepare/mount state for a box.
///
/// This is a **cache/hint, not authoritative**. Commands re-check live state
/// (`cfs_path.exists()`, `mountpoint -q`) because mounts disappear across
/// reboots. Paths are not stored here: they are always derivable from the box
/// name via `Paths::box_paths`.
///
/// The field names (`built`, `last_built_at`) are kept for on-disk stability
/// of `metadata.json`; user-facing strings say "prepared".
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct BoxMetadata {
    #[serde(default)]
    pub built: bool,
    #[serde(default)]
    pub mounted: bool,
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
        let data = std::fs::read(path)
            .with_context(|| format!("failed to read {}", path.display()))?;
        let meta = serde_json::from_slice(&data)
            .with_context(|| format!("failed to parse {}", path.display()))?;
        Ok(meta)
    }
}

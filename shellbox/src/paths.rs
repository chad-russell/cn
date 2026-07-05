use anyhow::{Context, Result, anyhow, bail};
use nix::unistd::{Uid, User};
use std::path::PathBuf;

#[derive(Debug, Clone)]
pub struct Paths {
    pub data_dir: PathBuf,
    pub state_dir: PathBuf,
}

/// All filesystem locations that refer to a single box.
///
/// Authored files live under `dir` (which may be a symlink into a dotfiles
/// repo). Derived/recreatable artifacts live under `state_dir`/`<name>/` so
/// that symlinked boxes don't drag machine-specific state into version control
/// and so `rm` can drop artifacts without touching the manifest.
#[derive(Debug, Clone)]
pub struct BoxPaths {
    /// `boxes/<name>` — authored files only (the manifest). May be a symlink.
    pub dir: PathBuf,
    /// `dir/shellbox.toml` — the single source of truth.
    pub manifest_path: PathBuf,

    /// `state/<name>` — all per-box derived state.
    pub state_dir: PathBuf,
    /// `state/<name>/metadata.json` — derived prepare/mount cache.
    pub metadata_path: PathBuf,
    /// `state/<name>/image.cfs` — composefs image.
    pub cfs_path: PathBuf,
    /// `state/<name>/rootfs` — exported rootfs (prepare input).
    pub rootfs_path: PathBuf,
}

impl Paths {
    pub fn new() -> Result<Self> {
        let home = home_dir_for_shellbox()?;

        Ok(Self {
            data_dir: home.join(".local/share/shellbox"),
            state_dir: home.join(".local/state/shellbox"),
        })
    }

    pub fn ensure_base_dirs(&self) -> Result<()> {
        std::fs::create_dir_all(self.boxes_dir())
            .with_context(|| format!("failed to create {}", self.boxes_dir().display()))?;
        std::fs::create_dir_all(self.store_dir())
            .with_context(|| format!("failed to create {}", self.store_dir().display()))?;
        std::fs::create_dir_all(self.exports_bin_dir())
            .with_context(|| format!("failed to create {}", self.exports_bin_dir().display()))?;
        std::fs::create_dir_all(self.exports_metadata_dir()).with_context(|| {
            format!("failed to create {}", self.exports_metadata_dir().display())
        })?;
        std::fs::create_dir_all(self.sessions_dir())
            .with_context(|| format!("failed to create {}", self.sessions_dir().display()))?;
        Ok(())
    }

    pub fn boxes_dir(&self) -> PathBuf {
        self.data_dir.join("boxes")
    }

    pub fn store_dir(&self) -> PathBuf {
        self.data_dir.join("store")
    }

    pub fn exports_dir(&self) -> PathBuf {
        self.data_dir.join("exports")
    }

    pub fn exports_bin_dir(&self) -> PathBuf {
        self.exports_dir().join("bin")
    }

    pub fn exports_metadata_dir(&self) -> PathBuf {
        self.exports_dir().join("metadata")
    }

    /// Top-level shared dir for ephemeral devshell sessions (not per-box).
    pub fn sessions_dir(&self) -> PathBuf {
        self.state_dir.join("sessions")
    }

    pub fn box_paths(&self, name: &str) -> BoxPaths {
        let dir = self.boxes_dir().join(name);
        let state_dir = self.state_dir.join(name);
        BoxPaths {
            manifest_path: dir.join("shellbox.toml"),
            metadata_path: state_dir.join("metadata.json"),
            cfs_path: state_dir.join("image.cfs"),
            rootfs_path: state_dir.join("rootfs"),
            state_dir,
            dir,
        }
    }
}

fn home_dir_for_shellbox() -> Result<PathBuf> {
    if Uid::effective().is_root()
        && let Some(path) = sudo_user_home()?
    {
        return Ok(path);
    }

    std::env::var_os("HOME")
        .map(PathBuf::from)
        .context("failed to resolve HOME")
}

fn sudo_user_home() -> Result<Option<PathBuf>> {
    let Some(uid_str) = std::env::var_os("SUDO_UID") else {
        return Ok(None);
    };

    let uid: u32 = uid_str
        .to_string_lossy()
        .parse()
        .context("failed to parse SUDO_UID")?;
    let user = User::from_uid(Uid::from_raw(uid))?
        .ok_or_else(|| anyhow!("failed to resolve sudo user from uid {uid}"))?;

    if user.dir.as_os_str().is_empty() {
        bail!("sudo user home directory is empty");
    }

    Ok(Some(user.dir))
}

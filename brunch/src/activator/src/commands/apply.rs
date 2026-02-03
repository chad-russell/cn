use crate::{next_generation, state_dir, symlink_atomic};
use anyhow::{Context, Result};
use dirs;
use std::path::{Path, PathBuf};

pub fn run(project_path: &Path) -> Result<()> {
    let project_path = std::fs::canonicalize(project_path)
        .context("Failed to resolve project path")?;

    let state = state_dir()?;
    let generations = state.join("generations");
    let current = state.join("current");

    std::fs::create_dir_all(&generations).context("Failed to create generations directory")?;

    let gen_num = next_generation(&generations).context("Failed to get next generation number")?;
    let gen_path = generations.join(gen_num.to_string());

    log::info!("Building project: {}", project_path.display());

    let status = std::process::Command::new("brioche")
        .arg("build")
        .arg("-p")
        .arg(&project_path)
        .arg("-o")
        .arg(&gen_path)
        .status()
        .context("Failed to execute brioche build")?;

    if !status.success() {
        anyhow::bail!("Brioche build failed");
    }

    let old_current = if current.exists() {
        std::fs::read_link(&current).ok()
    } else {
        None
    };

    symlink_atomic(&gen_path, &current).context("Failed to update current symlink")?;

    link_desktop_assets(&current).context("Failed to link desktop assets")?;
    link_files(&current).context("Failed to link home files")?;

    if let Some(old_path) = old_current {
        cleanup_files(&old_path, &gen_path).context("Failed to cleanup old files")?;
    }

    println!("Applied generation {}", gen_num);
    Ok(())
}

pub fn link_desktop_assets(current: &Path) -> Result<()> {
    let home = std::env::var("HOME").context("HOME environment variable not set")?;
    let local_bin = PathBuf::from(format!("{}/.local/bin", home));
    let local_share = PathBuf::from(format!("{}/.local/share", home));
    let data_dir = dirs::data_local_dir().unwrap_or_else(|| local_share.clone());

    let apps_dir = data_dir.join("applications");
    let icons_dir = data_dir.join("icons/hicolor/scalable/apps");

    std::fs::create_dir_all(&local_bin).context("Failed to create bin directory")?;
    std::fs::create_dir_all(&apps_dir).context("Failed to create applications directory")?;
    std::fs::create_dir_all(&icons_dir).context("Failed to create icons directory")?;

    let gen_bin = current.join("bin");
    let gen_apps = current.join("share/applications");
    let gen_icons = current.join("share/icons/hicolor/scalable/apps");

    if gen_bin.exists() {
        for entry in std::fs::read_dir(&gen_bin).context("Failed to read gen bin")? {
            let entry = entry.context("Failed to read directory entry")?;
            let src = entry.path();
            let name = src
                .file_name()
                .context("Path has no filename")?;
            let dest = local_bin.join(name);

            symlink_atomic(&src, &dest).context(format!(
                "Failed to link binary {} -> {}",
                src.display(),
                dest.display()
            ))?;
        }
    }

    if gen_apps.exists() {
        for entry in std::fs::read_dir(&gen_apps).context("Failed to read gen apps")? {
            let entry = entry.context("Failed to read directory entry")?;
            let src = entry.path();
            let name = src
                .file_name()
                .context("Path has no filename")?;
            let dest = apps_dir.join(name);

            symlink_atomic(&src, &dest).context(format!(
                "Failed to link desktop file {} -> {}",
                src.display(),
                dest.display()
            ))?;
        }
    }

    if gen_icons.exists() {
        for entry in std::fs::read_dir(&gen_icons).context("Failed to read gen icons")? {
            let entry = entry.context("Failed to read directory entry")?;
            let src = entry.path();
            let name = src
                .file_name()
                .context("Path has no filename")?;
            let dest = icons_dir.join(name);

            symlink_atomic(&src, &dest).context(format!(
                "Failed to link icon {} -> {}",
                src.display(),
                dest.display()
            ))?;
        }
    }

    Ok(())
}

pub fn link_files(current: &Path) -> Result<()> {
    let files_dir = current.join("files");
    if !files_dir.exists() {
        return Ok(());
    }

    let root_dir = files_dir.join("root");
    if root_dir.exists() {
        link_dir_recursive(&root_dir, &PathBuf::from("/"))?;
    }

    let home_dir = files_dir.join("home");
    if home_dir.exists() {
        let home = std::env::var("HOME").context("HOME environment variable not set")?;
        link_dir_recursive(&home_dir, &PathBuf::from(home))?;
    }

    Ok(())
}

fn link_dir_recursive(source_root: &Path, target_root: &Path) -> Result<()> {
    for entry in walkdir::WalkDir::new(source_root) {
        let entry = entry?;
        if !entry.file_type().is_file() && !entry.file_type().is_symlink() {
            continue;
        }

        let path = entry.path();
        let rel_path = path.strip_prefix(source_root)?;
        let target_sys_path = target_root.join(rel_path);

        symlink_atomic(path, &target_sys_path).context(format!(
            "Failed to link file {} -> {}",
            path.display(),
            target_sys_path.display()
        ))?;
    }
    Ok(())
}

pub fn cleanup_files(old_gen: &Path, new_gen: &Path) -> Result<()> {
    let state = state_dir()?;
    let current_link = state.join("current");

    let old_files_dir = old_gen.join("files");
    let new_files_dir = new_gen.join("files");

    if !old_files_dir.exists() {
        return Ok(());
    }

    cleanup_dir_recursive(
        &old_files_dir.join("root"),
        &new_files_dir.join("root"),
        &PathBuf::from("/"),
        &current_link.join("files/root")
    )?;

    let home = std::env::var("HOME").ok();
    if let Some(home_path) = home {
        cleanup_dir_recursive(
            &old_files_dir.join("home"),
            &new_files_dir.join("home"),
            &PathBuf::from(home_path),
            &current_link.join("files/home")
        )?;
    }

    Ok(())
}

fn cleanup_dir_recursive(old_root: &Path, new_root: &Path, target_root: &Path, expected_link_base: &Path) -> Result<()> {
    if !old_root.exists() {
        return Ok(());
    }

    for entry in walkdir::WalkDir::new(old_root) {
        let entry = entry?;
        if !entry.file_type().is_file() && !entry.file_type().is_symlink() {
            continue;
        }

        let path = entry.path();
        let rel_path = path.strip_prefix(old_root)?;
        
        let new_path = new_root.join(rel_path);
        if !new_path.exists() {
            let target_sys_path = target_root.join(rel_path);
            let expected_target = expected_link_base.join(rel_path);
            
            log::debug!("Checking cleanup for: {}", target_sys_path.display());

            if target_sys_path.is_symlink() {
                if let Ok(target) = std::fs::read_link(&target_sys_path) {
                    log::debug!("  Target: {}", target.display());
                    log::debug!("  Expected: {}", expected_target.display());
                    
                    if target == expected_target {
                        log::info!("Removing managed file: {}", target_sys_path.display());
                        std::fs::remove_file(&target_sys_path).context("Failed to remove old symlink")?;
                    }
                }
            }
        }
    }
    Ok(())
}

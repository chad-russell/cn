use crate::{next_generation, state_dir, symlink_atomic};
use anyhow::{Context, Result};
use dirs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::Command;

pub fn run(project_path: &Path, target: &str) -> Result<()> {
    let project_path =
        std::fs::canonicalize(project_path).context("Failed to resolve project path")?;
    let build_target = format!("{}^{}", project_path.display(), target);

    let state = state_dir()?;
    let generations = state.join("generations");
    let current = state.join("current");

    std::fs::create_dir_all(&generations).context("Failed to create generations directory")?;

    let gen_num = next_generation(&generations).context("Failed to get next generation number")?;
    let gen_path = generations.join(gen_num.to_string());

    log::info!("Building project: {}", build_target);

    let status = std::process::Command::new("brioche")
        .arg("build")
        .arg(&build_target)
        .arg("-o")
        .arg(&gen_path)
        .status()
        .context("Failed to execute brioche build")?;

    if !status.success() {
        anyhow::bail!("Brioche build failed");
    }

    let has_system_units = gen_path.join("systemd/system").exists();
    let elevated = if has_system_units {
        prompt_for_elevation()?
    } else {
        false
    };

    let old_current = if current.exists() {
        std::fs::read_link(&current).ok()
    } else {
        None
    };

    symlink_atomic(&gen_path, &current).context("Failed to update current symlink")?;

    if let Some(ref old_path) = old_current {
        cleanup_systemd(old_path, &gen_path, elevated)
            .context("Failed to cleanup old systemd units")?;
    }

    link_systemd(&current, elevated).context("Failed to link systemd units")?;

    link_desktop_assets(&current).context("Failed to link desktop assets")?;
    link_files(&current).context("Failed to link home files")?;

    if let Some(ref old_path) = old_current {
        cleanup_files(old_path, &gen_path).context("Failed to cleanup old files")?;
    }

    reconcile_flatpaks(&current, old_current.as_deref())
        .context("Failed to reconcile flatpaks")?;

    println!("Applied generation {}", gen_num);
    Ok(())
}

fn prompt_for_elevation() -> Result<bool> {
    println!("System-level systemd units detected.");
    print!("Apply with elevated privileges? [y/N]: ");
    io::stdout().flush()?;

    let mut input = String::new();
    io::stdin().read_line(&mut input)?;

    Ok(input.trim().to_lowercase() == "y")
}

fn run_elevated_command(args: &[&str]) -> Result<()> {
    let status = Command::new("pkexec")
        .args(args)
        .status()
        .or_else(|_| Command::new("sudo").args(args).status())?;

    if !status.success() {
        log::warn!("Elevated command failed: {:?}", args);
    }
    Ok(())
}

pub fn link_systemd(current: &Path, elevated: bool) -> Result<()> {
    let systemd_dir = current.join("systemd");
    let systemd_state_dir = current.join("systemd-state");
    if !systemd_dir.exists() {
        return Ok(());
    }

    let user_dir = systemd_dir.join("user");
    if user_dir.exists() {
        let config_dir = dirs::config_dir().context("Failed to get config directory")?;
        let target_dir = config_dir.join("systemd/user");
        link_systemd_dir(&user_dir, &target_dir, &user_dir, false)?;
        daemon_reload(false)?;
        reconcile_enablement(&systemd_state_dir.join("user"), false)?;
    }

    if elevated {
        let system_dir = systemd_dir.join("system");
        if system_dir.exists() {
            let target_dir = PathBuf::from("/etc/systemd/system");
            link_systemd_dir_elevated(&system_dir, &target_dir, &system_dir)?;
            daemon_reload(true)?;
            reconcile_enablement(&systemd_state_dir.join("system"), true)?;
        }
    } else if systemd_dir.join("system").exists() {
        log::warn!("System units present but no elevated privileges - skipping system units");
    }

    Ok(())
}

fn link_systemd_dir(
    source_root: &Path,
    target_root: &Path,
    _expected_link_base: &Path,
    _is_system: bool,
) -> Result<()> {
    for entry in walkdir::WalkDir::new(source_root) {
        let entry = entry?;
        let path = entry.path();

        if path.ends_with("executables") {
            continue;
        }

        if !entry.file_type().is_file() && !entry.file_type().is_symlink() {
            continue;
        }

        let rel_path = path.strip_prefix(source_root)?;
        let target_sys_path = target_root.join(rel_path);

        symlink_atomic(path, &target_sys_path).context(format!(
            "Failed to link systemd unit {} -> {}",
            path.display(),
            target_sys_path.display()
        ))?;
    }
    Ok(())
}

fn daemon_reload(is_system: bool) -> Result<()> {
    if is_system {
        run_elevated_command(&["systemctl", "daemon-reload"])?;
    } else {
        let status = Command::new("systemctl")
            .args(["--user", "daemon-reload"])
            .status()
            .context("Failed to reload user systemd daemon")?;

        if !status.success() {
            anyhow::bail!("User systemd daemon-reload failed");
        }
    }

    Ok(())
}

fn read_units_list(path: &Path) -> Result<Vec<String>> {
    if !path.exists() {
        return Ok(Vec::new());
    }

    let contents = std::fs::read_to_string(path)
        .context(format!("Failed to read unit state file {}", path.display()))?;

    Ok(contents
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(str::to_string)
        .collect())
}

fn reconcile_enablement(state_dir: &Path, is_system: bool) -> Result<()> {
    if !state_dir.exists() {
        return Ok(());
    }

    for unit in read_units_list(&state_dir.join("enabled.units"))? {
        if is_system {
            run_elevated_command(&["systemctl", "enable", &unit])?;
        } else {
            let status = Command::new("systemctl")
                .args(["--user", "enable", &unit])
                .status()
                .context(format!("Failed to enable user unit {}", unit))?;

            if !status.success() {
                anyhow::bail!("Failed to enable user unit {}", unit);
            }
        }
    }

    for unit in read_units_list(&state_dir.join("disabled.units"))? {
        if is_system {
            run_elevated_command(&["systemctl", "disable", &unit])?;
        } else {
            let status = Command::new("systemctl")
                .args(["--user", "disable", &unit])
                .status()
                .context(format!("Failed to disable user unit {}", unit))?;

            if !status.success() {
                anyhow::bail!("Failed to disable user unit {}", unit);
            }
        }
    }

    Ok(())
}

fn link_systemd_dir_elevated(
    source_root: &Path,
    target_root: &Path,
    _expected_link_base: &Path,
) -> Result<()> {
    for entry in walkdir::WalkDir::new(source_root) {
        let entry = entry?;
        let path = entry.path();

        if path.ends_with("executables") {
            continue;
        }

        if !entry.file_type().is_file() && !entry.file_type().is_symlink() {
            continue;
        }

        let rel_path = path.strip_prefix(source_root)?;
        let target_sys_path = target_root.join(rel_path);
        let parent = target_sys_path.parent().context("No parent directory")?;

        let mkdir_cmd = format!("mkdir -p '{}'", parent.display());
        let ln_cmd = format!(
            "ln -sf '{}' '{}'",
            path.display(),
            target_sys_path.display()
        );

        run_elevated_command(&["sh", "-c", &format!("{} && {}", mkdir_cmd, ln_cmd)])?;
    }
    Ok(())
}

pub fn cleanup_systemd(old_gen: &Path, new_gen: &Path, elevated: bool) -> Result<()> {
    let old_systemd_dir = old_gen.join("systemd");
    let new_systemd_dir = new_gen.join("systemd");

    if !old_systemd_dir.exists() {
        return Ok(());
    }

    let config_dir = dirs::config_dir().context("Failed to get config directory")?;

    cleanup_systemd_dir(
        &old_systemd_dir.join("user"),
        &new_systemd_dir.join("user"),
        &config_dir.join("systemd/user"),
        &old_systemd_dir.join("user"),
        false,
    )?;

    if elevated {
        cleanup_systemd_dir(
            &old_systemd_dir.join("system"),
            &new_systemd_dir.join("system"),
            &PathBuf::from("/etc/systemd/system"),
            &old_systemd_dir.join("system"),
            true,
        )?;
    }

    Ok(())
}

fn cleanup_systemd_dir(
    old_root: &Path,
    new_root: &Path,
    target_root: &Path,
    expected_link_base: &Path,
    is_system: bool,
) -> Result<()> {
    if !old_root.exists() {
        return Ok(());
    }

    for entry in walkdir::WalkDir::new(old_root) {
        let entry = entry?;
        let path = entry.path();

        if path.ends_with("executables") {
            continue;
        }

        if !entry.file_type().is_file() && !entry.file_type().is_symlink() {
            continue;
        }

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
                        log::info!(
                            "Removing managed systemd unit: {}",
                            target_sys_path.display()
                        );

                        let unit_name = rel_path.file_name().and_then(|n| n.to_str()).unwrap_or("");

                        if is_system {
                            let _ =
                                run_elevated_command(&["systemctl", "disable", "--now", unit_name]);
                            let rm_cmd = format!("rm -f '{}'", target_sys_path.display());
                            let _ = run_elevated_command(&["sh", "-c", &rm_cmd]);
                        } else {
                            let _ = Command::new("systemctl")
                                .args(["--user", "disable", "--now", unit_name])
                                .status();
                            std::fs::remove_file(&target_sys_path)
                                .context("Failed to remove old unit symlink")?;
                        }
                    }
                }
            }
        }
    }
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
            let name = src.file_name().context("Path has no filename")?;
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
            let name = src.file_name().context("Path has no filename")?;
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
            let name = src.file_name().context("Path has no filename")?;
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
        &current_link.join("files/root"),
    )?;

    let home = std::env::var("HOME").ok();
    if let Some(home_path) = home {
        cleanup_dir_recursive(
            &old_files_dir.join("home"),
            &new_files_dir.join("home"),
            &PathBuf::from(home_path),
            &current_link.join("files/home"),
        )?;
    }

    Ok(())
}

fn cleanup_dir_recursive(
    old_root: &Path,
    new_root: &Path,
    target_root: &Path,
    expected_link_base: &Path,
) -> Result<()> {
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
                        std::fs::remove_file(&target_sys_path)
                            .context("Failed to remove old symlink")?;
                    }
                }
            }
        }
    }
    Ok(())
}

/// Reconcile declaratively managed Flatpak applications.
///
/// Reads the flatpak manifest from the current generation and:
/// - Installs any flatpaks not yet present
/// - Uninstalls flatpaks that were managed but removed from config
fn reconcile_flatpaks(current: &Path, old_gen: Option<&Path>) -> Result<()> {
    let flatpak_dir = current.join("flatpaks");
    if !flatpak_dir.exists() {
        // No flatpak config in this generation — check if we need to
        // clean up flatpaks from a previous generation.
        if let Some(old) = old_gen {
            let old_flatpak_dir = old.join("flatpaks");
            if old_flatpak_dir.exists() {
                let old_list = read_flatpak_list(&old_flatpak_dir.join("managed.list"))?;
                uninstall_flatpaks(&old_list)?;
            }
        }
        return Ok(());
    }

    let desired = read_flatpak_list(&flatpak_dir.join("managed.list"))?;
    if desired.is_empty() {
        return Ok(());
    }

    // Get currently installed flatpaks
    let installed = get_installed_flatpaks()?;

    // Install missing flatpaks
    let mut to_install: Vec<&str> = Vec::new();
    for id in &desired {
        if !installed.contains(&id.to_string()) {
            to_install.push(id);
        }
    }

    if !to_install.is_empty() {
        println!("Installing {} flatpak(s)...", to_install.len());
        for id in &to_install {
            println!("  installing {}", id);
        }

        let mut cmd = Command::new("flatpak");
        cmd.arg("install").arg("--noninteractive").arg("--or-update");
        for id in &to_install {
            cmd.arg(id);
        }

        let status = cmd.status().context("Failed to run flatpak install")?;
        if !status.success() {
            log::warn!("flatpak install returned non-zero exit status");
        }
    }

    // Uninstall flatpaks that were previously managed but no longer desired
    if let Some(old) = old_gen {
        let old_flatpak_dir = old.join("flatpaks");
        if old_flatpak_dir.exists() {
            let old_list = read_flatpak_list(&old_flatpak_dir.join("managed.list"))?;
            let desired_set: std::collections::HashSet<String> =
                desired.iter().map(|s| s.to_string()).collect();

            let to_remove: Vec<String> = old_list
                .iter()
                .filter(|id| !desired_set.contains(*id))
                .cloned()
                .collect();

            uninstall_flatpaks(&to_remove)?;
        }
    }

    if to_install.is_empty() {
        println!("Flatpaks up to date ({} managed)", desired.len());
    }

    Ok(())
}

fn uninstall_flatpaks(ids: &[String]) -> Result<()> {
    if ids.is_empty() {
        return Ok(());
    }

    println!("Uninstalling {} removed flatpak(s)...", ids.len());
    for id in ids {
        println!("  removing {}", id);
    }

    let mut cmd = Command::new("flatpak");
    cmd.arg("uninstall").arg("--noninteractive");
    for id in ids {
        cmd.arg(id);
    }

    let status = cmd.status().context("Failed to run flatpak uninstall")?;
    if !status.success() {
        log::warn!("flatpak uninstall returned non-zero exit status");
    }

    Ok(())
}

fn read_flatpak_list(path: &Path) -> Result<Vec<String>> {
    if !path.exists() {
        return Ok(Vec::new());
    }
    let contents = std::fs::read_to_string(path)
        .context(format!("Failed to read flatpak list: {}", path.display()))?;
    Ok(contents
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(str::to_string)
        .collect())
}

fn get_installed_flatpaks() -> Result<std::collections::HashSet<String>> {
    let output = Command::new("flatpak")
        .args(["list", "--app", "--columns=application"])
        .output()
        .context("Failed to run flatpak list")?;

    if !output.status.success() {
        // flatpak might not be installed yet — return empty set
        log::warn!("flatpak list failed, assuming no flatpaks installed");
        return Ok(std::collections::HashSet::new());
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    Ok(stdout
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(str::to_string)
        .collect())
}

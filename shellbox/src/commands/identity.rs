use super::common::{default_shell, home_dir};
use crate::config::BoxManifest;
use crate::util::command_output;
use anyhow::{Context, Result};
use nix::unistd::{Gid, Group, Uid, User};
use std::path::Path;
use std::process::Command;

pub(super) fn inject_runtime_identity(rootfs: &Path) -> Result<()> {
    let etc = rootfs.join("etc");
    std::fs::create_dir_all(&etc)
        .with_context(|| format!("failed to create {}", etc.display()))?;

    let uid = Uid::current().as_raw();
    let fallback_gid = Gid::current().as_raw();
    let user = User::from_uid(Uid::current())?;
    let primary_gid = user.as_ref().map(|u| u.gid.as_raw()).unwrap_or(fallback_gid);
    let username = user
        .as_ref()
        .map(|u| u.name.clone())
        .filter(|name| !name.is_empty())
        .unwrap_or_else(|| std::env::var("USER").unwrap_or_else(|_| format!("user{uid}")));
    let home = home_dir()?;
    let shell = default_shell(rootfs);
    let gids = current_group_ids(primary_gid)?;

    let mut group_names: Vec<(u32, String)> = Vec::new();
    for gid in &gids {
        let name = Group::from_gid(Gid::from_raw(*gid))?
            .map(|g| g.name)
            .filter(|n| !n.is_empty())
            .unwrap_or_else(|| format!("gid{gid}"));
        group_names.push((*gid, name));
    }

    merge_passwd(&etc.join("passwd"), uid, primary_gid, &username, &home, &shell)?;
    merge_group(&etc.join("group"), &username, &group_names)?;
    ensure_nsswitch_files(&etc.join("nsswitch.conf"))?;
    Ok(())
}

pub(super) fn inject_name_resolution(rootfs: &Path) -> Result<()> {
    let etc = rootfs.join("etc");
    std::fs::create_dir_all(&etc)
        .with_context(|| format!("failed to create {}", etc.display()))?;
    copy_host_file(Path::new("/etc/resolv.conf"), &etc.join("resolv.conf"))?;
    copy_host_file(Path::new("/etc/hosts"), &etc.join("hosts"))?;
    Ok(())
}

pub(super) fn inject_desktop_mount_points(rootfs: &Path) -> Result<()> {
    let uid = nix::unistd::Uid::current().as_raw();
    let dir = rootfs.join("run").join("user").join(uid.to_string());
    std::fs::create_dir_all(&dir)
        .with_context(|| format!("failed to create {}", dir.display()))?;
    Ok(())
}

/// Pre-create the in-box bind targets for `[host]` tools. bwrap binds *over*
/// existing paths, and the composefs root is read-only at runtime, so the
/// placeholders must be baked in at prepare time (same pattern as the desktop
/// mount points and name-resolution files above). No-op when no host tools are
/// declared, so non-host boxes keep a clean rootfs.
pub(super) fn inject_host_exec_mount_points(rootfs: &Path, manifest: &BoxManifest) -> Result<()> {
    if manifest.host.tools.is_empty() {
        return Ok(());
    }
    // INBOX_* constants are absolute in-box paths ("/run/..."); relativize
    // them against the rootfs being assembled.
    let helper_rel = crate::host_exec::INBOX_HELPER.trim_start_matches('/');
    let bin_rel = crate::host_exec::INBOX_HOSTBIN.trim_start_matches('/');

    // Directory: bind target for the per-tool wrapper dir.
    let bin_dir = rootfs.join(bin_rel);
    std::fs::create_dir_all(&bin_dir)
        .with_context(|| format!("failed to create {}", bin_dir.display()))?;
    // Regular file: bind target for the static helper binary. Its parent
    // (/run) already exists, but create it defensively in case INBOX_HELPER
    // ever moves deeper.
    let helper_file = rootfs.join(helper_rel);
    if let Some(parent) = helper_file.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(&helper_file, [])
        .with_context(|| format!("failed to create {}", helper_file.display()))?;
    Ok(())
}

fn copy_host_file(src: &Path, dst: &Path) -> Result<()> {
    match std::fs::read(src) {
        Ok(data) => {
            std::fs::write(dst, data)
                .with_context(|| format!("failed to write {}", dst.display()))?;
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            eprintln!("warning: host file {} not found; skipping", src.display());
        }
        Err(e) => return Err(e).with_context(|| format!("failed to read {}", src.display())),
    }
    Ok(())
}

fn merge_passwd(
    path: &Path,
    uid: u32,
    gid: u32,
    username: &str,
    home: &Path,
    shell: &str,
) -> Result<()> {
    let existing = std::fs::read_to_string(path).unwrap_or_default();
    let mut lines: Vec<String> = existing
        .lines()
        .filter(|line| {
            let mut fields = line.split(':');
            let name = fields.next().unwrap_or("");
            let id = fields.nth(1).and_then(|s| s.parse::<u32>().ok());
            !(name == username || id == Some(uid))
        })
        .map(str::to_string)
        .collect();
    lines.push(format!("{}:x:{}:{}::{}:{}", username, uid, gid, home.display(), shell));
    write_lines(path, &lines)?;
    Ok(())
}

fn merge_group(path: &Path, username: &str, groups: &[(u32, String)]) -> Result<()> {
    let existing = std::fs::read_to_string(path).unwrap_or_default();
    let mut lines: Vec<Vec<String>> = existing
        .lines()
        .filter(|line| !line.is_empty())
        .map(|line| line.split(':').map(str::to_string).collect())
        .collect();

    for (gid, name) in groups {
        if let Some(row) = lines
            .iter_mut()
            .find(|fields| fields.get(2).and_then(|s| s.parse::<u32>().ok()) == Some(*gid))
        {
            let members = row.get_mut(3).unwrap();
            let mut list: Vec<&str> = members.split(',').filter(|s| !s.is_empty()).collect();
            if !list.iter().any(|m| *m == username) {
                list.push(username);
            }
            *members = list.join(",");
        } else {
            lines.push(vec![
                name.clone(),
                "x".to_string(),
                gid.to_string(),
                username.to_string(),
            ]);
        }
    }

    let rendered: Vec<String> = lines.into_iter().map(|fields| fields.join(":")).collect();
    write_lines(path, &rendered)?;
    Ok(())
}

fn ensure_nsswitch_files(path: &Path) -> Result<()> {
    let existing = std::fs::read_to_string(path).unwrap_or_default();
    let passwd_ok = existing.lines().any(|line| line.starts_with("passwd:") && line.contains("files"));
    let group_ok = existing.lines().any(|line| line.starts_with("group:") && line.contains("files"));
    if passwd_ok && group_ok {
        return Ok(());
    }
    let hosts_line = existing
        .lines()
        .find(|line| line.starts_with("hosts:"))
        .unwrap_or("hosts: files dns myhostname")
        .to_string();
    let content = format!("passwd: files\ngroup: files\nshadow: files\n{}\n", hosts_line);
    std::fs::write(path, content).with_context(|| format!("failed to write {}", path.display()))?;
    Ok(())
}

fn write_lines(path: &Path, lines: &[String]) -> Result<()> {
    let mut content = lines.join("\n");
    if !content.is_empty() {
        content.push('\n');
    }
    std::fs::write(path, content).with_context(|| format!("failed to write {}", path.display()))?;
    Ok(())
}

fn current_group_ids(primary_gid: u32) -> Result<Vec<u32>> {
    let output = command_output(Command::new("id").arg("-G"))?;
    let mut gids = Vec::new();
    for raw in output.split_whitespace() {
        let gid: u32 = raw
            .parse()
            .with_context(|| format!("failed to parse gid '{raw}' from `id -G`"))?;
        if !gids.contains(&gid) {
            gids.push(gid);
        }
    }
    if !gids.contains(&primary_gid) {
        gids.insert(0, primary_gid);
    }
    Ok(gids)
}

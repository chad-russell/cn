use super::common::{home_dir, is_mountpoint, normalize_tools};
use super::wrappers::write_wrapper_script;
use crate::config::BoxManifest;
use crate::paths::{BoxPaths, Paths};
use crate::util::run_command_inherit;
use anyhow::{Context, Result};
use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::process::Command;
use tempfile::{Builder, TempDir};

pub(super) fn run_box_command(
    box_paths: &BoxPaths,
    store: &Path,
    manifest: &BoxManifest,
    cmd: &[String],
) -> Result<std::process::ExitStatus> {
    let env = manifest.shell_env();
    let host_tools = normalize_tools(manifest.host_tools())?;

    if is_mountpoint(&box_paths.mount_path) {
        let host_session = if host_tools.is_empty() {
            None
        } else {
            Some(crate::host_exec::HostExecSession::start(&host_tools)?)
        };
        let result = run_in_box(&box_paths.mount_path, &env, host_session.as_ref(), cmd);
        // Drop before returning so the accept loop joins and the socket is
        // cleaned up (run then calls process::exit, which would otherwise
        // kill it mid-teardown).
        drop(host_session);
        result
    } else {
        run_in_box_fuse(&box_paths.cfs_path, store, &env, &host_tools, cmd)
    }
}

pub(super) fn create_shell_session(
    paths: &Paths,
    box_name: &str,
    tools: &[String],
    env_vars: &[(String, String)],
) -> Result<TempDir> {
    let session = Builder::new()
        .prefix(&format!("{box_name}-"))
        .tempdir_in(paths.sessions_dir())?;
    let bin_dir = session.path().join("bin");
    std::fs::create_dir_all(&bin_dir)
        .with_context(|| format!("failed to create {}", bin_dir.display()))?;
    for tool in tools {
        write_wrapper_script(&bin_dir.join(tool), box_name, tool, env_vars)?;
    }
    Ok(session)
}

pub(super) fn run_host_shell(
    box_name: &str,
    wrapper_dir: &Path,
    _env_vars: &[(String, String)],
) -> Result<std::process::ExitStatus> {
    let shell = std::env::var_os("SHELL").unwrap_or_else(|| OsString::from("/bin/sh"));
    let path = prepend_path(wrapper_dir)?;

    let mut command = Command::new(shell);
    command.env("PATH", path);
    command.env("SHELLBOX_NAME", box_name);
    command.env("SHELLBOX_EXPORT_MODE", "ephemeral");
    command.env("SHELLBOX_WRAPPER_DIR", wrapper_dir);
    // NOTE: declared box env vars (`[shell.env]`) are deliberately NOT applied
    // to the session here. They are inlined into each tool's wrapper script
    // (see `write_wrapper_script`), so they take effect only when a box tool
    // is actually invoked — never leaking onto unrelated programs run in the
    // session. This lets multiple boxes coexist in one shell: e.g. entering
    // the nvim box no longer redirects XDG for `git`, `ls`, etc.
    run_command_inherit(&mut command)
}

fn run_in_box(
    mount_path: &Path,
    env_vars: &[(String, String)],
    host: Option<&crate::host_exec::HostExecSession>,
    cmd: &[String],
) -> Result<std::process::ExitStatus> {
    let mut command = bwrap_command(mount_path, env_vars, host, cmd)?;
    run_command_inherit(&mut command)
}

/// Run a command inside a box using the fully rootless FUSE runtime (no mount
/// required). `image` is the composefs `.cfs` file; `store` is the
/// content-addressed object store. The bwrap invocation is identical to the
/// kernel-mount path — only the root source differs (a private FUSE mount
/// instead of a host-visible kernel composefs mount).
///
/// `host_tools` (rather than a started session) are passed in because the
/// session must be started *after* the `unshare(CLONE_NEWUSER|CLONE_NEWNS)`
/// inside `run_rootless` — starting it here would multithread the caller and
/// make `CLONE_NEWNS` fail with `EINVAL`.
fn run_in_box_fuse(
    image: &Path,
    store: &Path,
    env_vars: &[(String, String)],
    host_tools: &[String],
    cmd: &[String],
) -> Result<std::process::ExitStatus> {
    let env_vars_owned: Vec<(String, String)> = env_vars.to_vec();
    let cmd_owned: Vec<String> = cmd.to_vec();
    crate::fuse::run_rootless(image, store, host_tools, move |root, host| {
        // Same builder as the kernel path; unwraps are safe: inputs were
        // validated by the caller and only fail on HOME resolution.
        bwrap_command(root, &env_vars_owned, host, &cmd_owned)
            .expect("internal: bwrap_command failed inside FUSE runtime")
    })
}

/// Build the bwrap `Command` that runs `cmd` inside a box whose root is `root`.
/// Shared by the kernel-mount path (`run_in_box`) and the rootless FUSE path
/// (`run_in_box_fuse`), so the two are identical except for the root source.
fn bwrap_command(
    root: &Path,
    env_vars: &[(String, String)],
    host: Option<&crate::host_exec::HostExecSession>,
    cmd: &[String],
) -> Result<std::process::Command> {
    let home = home_dir()?;
    let cwd = std::env::current_dir().unwrap_or_else(|_| home.clone());
    let chdir = if cwd.starts_with(&home) {
        cwd
    } else {
        home.clone()
    };
    let user = std::env::var("USER").unwrap_or_else(|_| "user".to_string());
    let logname = std::env::var("LOGNAME").unwrap_or_else(|_| user.clone());

    // The host-tools shim dir is prepended to PATH so `[host]` tools resolve
    // ahead of everything else inside the box.
    let host_bin_prefix = host.map(|_| crate::host_exec::INBOX_HOSTBIN);

    let mut command = Command::new("bwrap");
    command
        .arg("--bind").arg(root).arg("/")
        .arg("--dev-bind").arg("/dev").arg("/dev")
        .arg("--proc").arg("/proc")
        .arg("--share-net")
        .arg("--ro-bind-try").arg("/etc/resolv.conf").arg("/etc/resolv.conf")
        .arg("--ro-bind-try").arg("/etc/hosts").arg("/etc/hosts")
        .arg("--tmpfs").arg("/tmp")
        .arg("--tmpfs").arg("/var")
        .arg("--dir").arg("/var/home")
        .arg("--bind").arg(&home).arg(&home)
        .arg("--chdir").arg(&chdir)
        .arg("--setenv").arg("HOME").arg(&home)
        .arg("--setenv").arg("USER").arg(&user)
        .arg("--setenv").arg("LOGNAME").arg(&logname)
        // Forward the host PATH into the box, so that user-installed tools
        // under $HOME (e.g. `~/.cargo/bin`, `~/.npm-global/bin`, `~/.local/bin`)
        // are visible to box processes — including agents (pi/opencode) that
        // shell out. This matches the host-integration feel of distrobox.
        //
        // We do NOT forward blindly: only entries that will actually resolve
        // inside the bwrap are kept (under $HOME, which is bound in, or present
        // in the box rootfs). Anything else (e.g. /nix/store, /opt/...) would
        // dangle and is dropped.
        //
        // Shellbox-managed wrapper directories (exports/bin, sessions/*/bin)
        // are explicitly excluded: their wrapper scripts invoke
        // `shellbox run <box>` again, so forwarding them into a box runtime
        // would shadow the box's own tools and recurse indefinitely. Only
        // genuine host tool directories are forwarded. The host-tools shim dir
        // (when present) is prepended separately and is safe to forward
        // because those wrappers exec the host-exec helper, not `shellbox run`.
        .arg("--setenv").arg("PATH").arg(forwarded_path(&home, root, host_bin_prefix)?);

    if let Some(host) = host {
        // Bind the helper binary and the per-tool wrapper dir into fixed
        // in-box paths, and tell the helper which socket to talk to.
        command
            .arg("--ro-bind").arg(host.helper_path()).arg(crate::host_exec::INBOX_HELPER)
            .arg("--bind").arg(host.hostbin_path()).arg(crate::host_exec::INBOX_HOSTBIN)
            .arg("--setenv").arg(crate::host_exec::SOCK_ENV).arg(host.socket_path());
    }

    if let Ok(xrd) = std::env::var("XDG_RUNTIME_DIR") {
        command.arg("--bind-try").arg(&xrd).arg(&xrd);
    }
    command.arg("--ro-bind-try").arg("/tmp/.X11-unix").arg("/tmp/.X11-unix");

    // Apply declared box env vars (verbatim) after the defaults so they win.
    for (k, v) in env_vars {
        command.arg("--setenv").arg(k).arg(v);
    }

    for part in cmd {
        command.arg(part);
    }

    Ok(command)
}

fn prepend_path(prefix: &Path) -> Result<OsString> {
    let mut value = prefix.as_os_str().to_os_string();
    if let Some(current) = std::env::var_os("PATH") {
        value.push(":");
        value.push(current);
    }
    Ok(value)
}

/// Build the `PATH` value for a box runtime: forward host PATH entries that
/// will resolve inside the bwrap, then append standard system dirs as fallback.
///
/// An entry is kept iff all of the following hold:
/// - it is under `$HOME` (always bound into the box) or exists in the box
///   rootfs (otherwise it would dangle), and
/// - it is NOT a shellbox-managed wrapper directory. The exports and sessions
///   dirs hold wrappers that call `shellbox run <box>`; forwarding them into a
///   box runtime would shadow the box's own binaries and recurse forever.
///
/// Standard system dirs are always appended as a fallback. Host entries
/// precede them so user-installed tools take precedence over same-named box
/// binaries. Order is preserved and duplicates are removed.
fn forwarded_path(home: &Path, mount_path: &Path, host_bin_prefix: Option<&str>) -> Result<OsString> {
    const SYSTEM_FALLBACK: &str =
        "/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin";

    // Shellbox-managed subtrees that must never be forwarded (recursion risk).
    let skip_prefixes: [PathBuf; 2] = [
        home.join(".local/share/shellbox"),
        home.join(".local/state/shellbox"),
    ];

    let mut kept: Vec<String> = Vec::new();
    let mut seen: std::collections::HashSet<String> = std::collections::HashSet::new();

    // Host-tools shim dir goes first so `[host]` tools win over everything.
    if let Some(prefix) = host_bin_prefix {
        kept.push(prefix.to_string());
        seen.insert(prefix.to_string());
    }

    if let Some(path) = std::env::var_os("PATH") {
        for raw in std::env::split_paths(&path) {
            let Some(s) = raw.to_str() else { continue };
            let cleaned = s.trim_end_matches('/');
            if cleaned.is_empty() || cleaned == "." {
                continue;
            }
            if !seen.insert(cleaned.to_string()) {
                continue; // dedup, first occurrence wins
            }
            let p = Path::new(cleaned);
            let is_shellbox_internal = skip_prefixes
                .iter()
                .any(|prefix| p.starts_with(prefix));
            if is_shellbox_internal {
                continue;
            }
            let reachable = p.starts_with(home) || mount_path.join(cleaned).exists();
            if reachable {
                kept.push(cleaned.to_string());
            }
        }
    }

    for d in SYSTEM_FALLBACK.split(':') {
        if seen.insert(d.to_string()) {
            kept.push(d.to_string());
        }
    }

    Ok(OsString::from(kept.join(":")))
}

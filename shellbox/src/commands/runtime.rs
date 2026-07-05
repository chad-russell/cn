use super::common::{home_dir, normalize_tools};
use super::wrappers::write_wrapper_script;
use crate::config::{Bind, BindMode, BoxManifest};
use crate::paths::{BoxPaths, Paths};
use crate::util::run_command_inherit;
use anyhow::{Context, Result, bail};
use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::process::Command;
use tempfile::{Builder, TempDir};

/// In-box absolute path the per-tool host wrapper dir is bind-mounted to.
pub(super) const INBOX_HOSTBIN: &str = "/run/shellbox-host-bin";

pub(super) fn run_box_command(
    box_paths: &BoxPaths,
    store: &Path,
    manifest: &BoxManifest,
    cmd: &[String],
) -> Result<std::process::ExitStatus> {
    let env = manifest.shell_env();
    let host_tools = normalize_tools(manifest.host_tools())?;

    // If the box declares [host] tools, build a temp dir of systemd-run
    // wrappers to bind-mount into the box. The temp dir outlives the bwrap
    // invocation (dropped at the end of this function, after the box exits).
    let host_wrappers = if host_tools.is_empty() {
        None
    } else {
        ensure_host_exec_available(&box_paths.rootfs_path)?;
        Some(create_host_wrappers(&host_tools)?)
    };

    // Always rootless: the box runs through the FUSE runtime, which mounts the
    // composefs image in a private user+mount namespace for the command's
    // lifetime. No kernel mount is involved.
    run_in_box_fuse(
        &box_paths.cfs_path,
        store,
        &env,
        host_wrappers.as_ref().map(TempDir::path),
        &manifest.binds,
        cmd,
    )
}

/// Fail clearly when a box declares `[host]` tools but its image doesn't
/// contain `systemd-run`. Container images don't ship it by default, so it's a
/// build-time (Containerfile) requirement; the read-only rootfs can't acquire
/// it at runtime.
fn ensure_host_exec_available(rootfs: &Path) -> Result<()> {
    const CANDIDATES: [&str; 3] = [
        "usr/bin/systemd-run",
        "usr/local/bin/systemd-run",
        "bin/systemd-run",
    ];
    if CANDIDATES.iter().any(|c| rootfs.join(c).exists()) {
        return Ok(());
    }
    bail!(
        "the box declares [host] tools, but `systemd-run` is not in its rootfs\n\
         host-exec runs the tool on the host via your user systemd manager\n\
         (`systemd-run --user`), reached through the bound $XDG_RUNTIME_DIR.\n\
         install it in the box image (e.g. `dnf install systemd` / \
         `apt install systemd`) and re-prepare"
    );
}

/// Build a temp dir of one wrapper per host tool. Each wrapper execs
/// `systemd-run --user --wait --pipe`, which asks the host's user systemd
/// manager to run the tool on the host (host rootfs, host binaries) and stream
/// stdio + the exit code back. The manager is reached over the bound
/// `$XDG_RUNTIME_DIR` socket and authenticates by uid. Bind-mounted into the
/// box at `INBOX_HOSTBIN` (prepended to PATH by `forwarded_path`).
fn create_host_wrappers(host_tools: &[String]) -> Result<TempDir> {
    use std::os::unix::fs::PermissionsExt;
    let dir = Builder::new()
        .prefix("shellbox-hostbin-")
        .tempdir()
        .context("failed to create host-tool wrapper tempdir")?;
    for tool in host_tools {
        let target = dir.path().join(tool);
        // Tool name is single-quoted defensively (validated to contain no
        // whitespace/'/' by normalize_tools, but quote anyway). $PWD is
        // host-valid: bwrap chdirs to cwd-or-$HOME, both under the bound $HOME.
        let quoted = tool.replace('\'', "'\"'\"'");
        let content = format!(
            "#!/usr/bin/env bash\n\
             exec systemd-run --user --wait --quiet --pipe --working-directory=\"$PWD\" -- '{quoted}' \"$@\"\n"
        );
        std::fs::write(&target, content)
            .with_context(|| format!("failed to write {}", target.display()))?;
        let mut perms = std::fs::metadata(&target)?.permissions();
        perms.set_mode(0o755);
        std::fs::set_permissions(&target, perms)?;
    }
    Ok(dir)
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

/// Run a command inside a box using the fully rootless FUSE runtime (no kernel
/// mount required). `image` is the composefs `.cfs` file; `store` is the
/// content-addressed object store. `host_wrappers`, when present, is a temp dir
/// of `systemd-run` wrappers (one per `[host]` tool) to bind-mount into the
/// box ahead of PATH. `binds` are the declared `[[binds]]` extra mounts.
fn run_in_box_fuse(
    image: &Path,
    store: &Path,
    env_vars: &[(String, String)],
    host_wrappers: Option<&Path>,
    binds: &[Bind],
    cmd: &[String],
) -> Result<std::process::ExitStatus> {
    let env_vars_owned: Vec<(String, String)> = env_vars.to_vec();
    let cmd_owned: Vec<String> = cmd.to_vec();
    let host_owned: Option<PathBuf> = host_wrappers.map(Path::to_path_buf);
    let binds_owned: Vec<Bind> = binds.to_vec();
    crate::fuse::run_rootless(image, store, move |root| {
        // unwrap is safe: inputs were validated by the caller and bwrap_command
        // only fails on HOME resolution.
        bwrap_command(
            root,
            &env_vars_owned,
            host_owned.as_deref(),
            &binds_owned,
            &cmd_owned,
        )
        .expect("internal: bwrap_command failed inside FUSE runtime")
    })
}

/// Build the bwrap `Command` that runs `cmd` inside a box whose root is `root`
/// (the private FUSE mountpoint set up by `run_rootless`).
fn bwrap_command(
    root: &Path,
    env_vars: &[(String, String)],
    host_wrappers: Option<&Path>,
    binds: &[Bind],
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
    let host_bin_prefix = host_wrappers.map(|_| INBOX_HOSTBIN);

    let mut command = Command::new("bwrap");
    command
        .arg("--bind")
        .arg(root)
        .arg("/")
        .arg("--dev-bind")
        .arg("/dev")
        .arg("/dev")
        .arg("--proc")
        .arg("/proc")
        .arg("--share-net")
        .arg("--ro-bind-try")
        .arg("/etc/resolv.conf")
        .arg("/etc/resolv.conf")
        .arg("--ro-bind-try")
        .arg("/etc/hosts")
        .arg("/etc/hosts")
        .arg("--tmpfs")
        .arg("/tmp")
        .arg("--tmpfs")
        .arg("/var")
        .arg("--dir")
        .arg("/var/home")
        .arg("--bind")
        .arg(&home)
        .arg(&home)
        .arg("--chdir")
        .arg(&chdir)
        .arg("--setenv")
        .arg("HOME")
        .arg(&home)
        .arg("--setenv")
        .arg("USER")
        .arg(&user)
        .arg("--setenv")
        .arg("LOGNAME")
        .arg(&logname)
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
        // because those wrappers exec `systemd-run`, not `shellbox run`.
        .arg("--setenv")
        .arg("PATH")
        .arg(forwarded_path(&home, root, host_bin_prefix)?);

    if let Some(wrapper_dir) = host_wrappers {
        // Bind the systemd-run wrapper dir into the box, prepended to PATH.
        command.arg("--bind").arg(wrapper_dir).arg(INBOX_HOSTBIN);
    }

    if let Ok(xrd) = std::env::var("XDG_RUNTIME_DIR") {
        command.arg("--bind-try").arg(&xrd).arg(&xrd);
    }
    command
        .arg("--ro-bind-try")
        .arg("/tmp/.X11-unix")
        .arg("/tmp/.X11-unix");

    // Layer declared `[[binds]]` after the fixed mounts so a guest may overlay
    // the rootfs (e.g. host `/sys` for GPU/Vulkan enumeration, `/run/dbus` for
    // the system bus). `optional = true` uses the `-try` variant to keep
    // headless boxes working when a path is absent; non-optional binds fail
    // loudly instead. The kernel-critical guests /, /dev, /proc are refused so
    // a box can't shadow its own essential mounts.
    for b in binds {
        let guest = b.guest.to_string_lossy();
        if matches!(guest.as_ref(), "/" | "/dev" | "/proc") {
            bail!(
                "bind guest '{}' would shadow a box-critical mount; \
                 pick a different guest path",
                guest
            );
        }
        let flag = match (b.mode, b.optional) {
            (BindMode::Ro, true) => "--ro-bind-try",
            (BindMode::Ro, false) => "--ro-bind",
            (BindMode::Rw, true) => "--bind-try",
            (BindMode::Rw, false) => "--bind",
            (BindMode::Dev, true) => "--dev-bind-try",
            (BindMode::Dev, false) => "--dev-bind",
        };
        command.arg(flag).arg(&b.host).arg(&b.guest);
    }

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
fn forwarded_path(home: &Path, root: &Path, host_bin_prefix: Option<&str>) -> Result<OsString> {
    const SYSTEM_FALLBACK: &str = "/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin";

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
            let is_shellbox_internal = skip_prefixes.iter().any(|prefix| p.starts_with(prefix));
            if is_shellbox_internal {
                continue;
            }
            let reachable = p.starts_with(home) || root.join(cleaned).exists();
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

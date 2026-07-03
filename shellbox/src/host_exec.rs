//! Host-exec: transparently run declared `[host]` tools on the host from inside
//! a box runtime.
//!
//! ## How it works
//!
//! When a box declares `[host] tools = ["podman", ...]`, `run` starts a
//! private, session-scoped Unix socket listener (this module) **in the parent
//! shellbox process**, then bind two things into the bwrap:
//!
//! - the static `shellbox-host-exec` helper binary → `/run/shellbox-host-exec`
//! - a temp dir of one wrapper per host tool → `/run/shellbox-host-bin`
//!   (each wrapper is `exec /run/shellbox-host-exec <tool> "$@"`)
//!
//! The wrapper dir is prepended to `PATH`, so `podman ps` inside the box
//! resolves to the wrapper → the helper → this socket → the parent shells out
//! to `systemd-run --user --wait --pipe -- podman ps` and streams stdio/exit
//! code back over the socket.
//!
//! ## Why a socket bridge instead of calling systemd-run directly in-box
//!
//! The box rootfs is read-only composefs; neither `systemd-run` nor a reliably
//! linkable host binary exists inside it. A tiny, near-zero-dep static helper
//! is the only thing that needs to run in-box, and it only does socket I/O. All
//! systemd policy stays in the main binary (on the host), where `systemd-run`
//! is guaranteed to exist.
//!
//! ## Lifetime
//!
//! The listener lives and dies with the box session: it is owned by the
//! `HostExecSession` guard, which is dropped when `run` returns (before
//! `process::exit`), so the socket is cleaned up and the accept loop joins.
//! In-flight host commands die with the parent process on exit (their stdio
//! pipes break), which matches the "nothing outlives the session" requirement.

use anyhow::{Context, Result, bail};
use std::io::{Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use tempfile::{Builder, TempDir};

/// Name of the companion helper binary, expected alongside the `shellbox`
/// executable.
pub const HELPER_NAME: &str = "shellbox-host-exec";

/// In-box absolute path the helper binary is bind-mounted to.
pub const INBOX_HELPER: &str = "/run/shellbox-host-exec";

/// In-box absolute path the per-tool wrapper dir is bind-mounted to.
pub const INBOX_HOSTBIN: &str = "/run/shellbox-host-bin";

/// Environment variable carrying the per-session socket path into the box.
pub const SOCK_ENV: &str = "SHELLBOX_HOST_EXEC_SOCK";

// --- wire protocol ---------------------------------------------------------
//
// After a helper connects, exactly one control message flows helper→parent,
// then a stream of framed chunks in both directions until the parent sends an
// exit frame and closes. All multi-byte integers are little-endian u32.
//
// Control message (helper → parent):
//   u32 cwd_len,   cwd bytes
//   u32 pty_flag   (0 = pipe, 1 = request a pty)
//   u32 n_env,     then n_env × (u32 k_len, k, u32 v_len, v)
//   u32 n_argv,    then n_argv × (u32 a_len, a)
//
// Stream frame (either direction), repeated:
//   u8  channel   (0 = stdin helper→parent,
//                  1 = stdout parent→helper,
//                  2 = stderr parent→helper,
//                  0xFF = exit, parent→helper, final)
//   u32 len
//   len bytes
//
// A channel-0 frame with len == 0 means stdin EOF on the helper side; the
// parent closes the spawned command's stdin. The exit frame carries a 4-byte
// LE exit code as its payload.

const CH_STDIN: u8 = 0;
const CH_STDOUT: u8 = 1;
const CH_STDERR: u8 = 2;
const CH_EXIT: u8 = 0xFF;

/// RAII handle for a running host-exec server. Drop stops the accept loop and
/// removes the socket file.
pub struct HostExecSession {
    socket_path: PathBuf,
    helper_path: PathBuf,
    _hostbin: TempDir,
    hostbin_path: PathBuf,
    shutdown: Arc<AtomicBool>,
    thread: Option<thread::JoinHandle<()>>,
}

impl HostExecSession {
    /// Bind the socket, write per-tool wrappers, and spawn the accept loop.
    ///
    /// `tools` are the (already-validated, deduped) `[host]` tool names.
    pub fn start(tools: &[String]) -> Result<Self> {
        let helper_path = std::env::current_exe()
            .context("failed to resolve current shellbox executable")?
            .parent()
            .context("shellbox executable has no parent dir")?
            .join(HELPER_NAME);
        if !helper_path.exists() {
            bail!(
                "host-exec helper not found at {}\n\
                 the '[host] tools' feature needs the '{HELPER_NAME}' binary installed \
                 alongside the shellbox binary",
                helper_path.display()
            );
        }

        let xrd = std::env::var_os("XDG_RUNTIME_DIR").context(
            "XDG_RUNTIME_DIR is not set; a running systemd user session is required for [host] tools",
        )?;
        let runtime_dir = PathBuf::from(&xrd).join("shellbox");
        std::fs::create_dir_all(&runtime_dir)
            .with_context(|| format!("failed to create {}", runtime_dir.display()))?;

        // Per-PID socket path: concurrent box sessions must not collide.
        let socket_path = runtime_dir.join(format!("host-exec-{}.sock", std::process::id()));
        let _ = std::fs::remove_file(&socket_path);
        let listener = UnixListener::bind(&socket_path)
            .with_context(|| format!("failed to bind {}", socket_path.display()))?;

        let hostbin = Builder::new()
            .prefix("shellbox-hostbin-")
            .tempdir()
            .context("failed to create host-tool wrapper tempdir")?;
        let hostbin_path = hostbin.path().to_path_buf();
        for tool in tools {
            write_host_wrapper(&hostbin_path.join(tool), tool)?;
        }

        let shutdown = Arc::new(AtomicBool::new(false));
        let accept_shutdown = shutdown.clone();
        let thread = thread::spawn(move || accept_loop(listener, accept_shutdown));

        Ok(HostExecSession {
            socket_path,
            helper_path,
            _hostbin: hostbin,
            hostbin_path,
            shutdown,
            thread: Some(thread),
        })
    }

    pub fn socket_path(&self) -> &Path {
        &self.socket_path
    }

    /// Host-side path to the helper binary (source for the in-box ro-bind).
    pub fn helper_path(&self) -> &Path {
        &self.helper_path
    }

    /// Host-side path to the wrapper tempdir (source for the in-box bind).
    pub fn hostbin_path(&self) -> &Path {
        &self.hostbin_path
    }
}

impl Drop for HostExecSession {
    fn drop(&mut self) {
        self.shutdown.store(true, Ordering::Release);
        // Unblock a blocked accept() so the loop re-checks the shutdown flag.
        let _ = UnixStream::connect(&self.socket_path);
        if let Some(handle) = self.thread.take() {
            let _ = handle.join();
        }
        let _ = std::fs::remove_file(&self.socket_path);
    }
}

fn write_host_wrapper(target: &Path, tool: &str) -> Result<()> {
    // The wrapper runs inside the box; the helper path is the fixed in-box
    // bind target. Tool name is quoted defensively.
    let quoted = tool.replace('\'', "'\"'\"'");
    let content = format!(
        "#!/usr/bin/env bash\nexec {INBOX_HELPER} '{quoted}' \"$@\"\n"
    );
    std::fs::write(target, content)
        .with_context(|| format!("failed to write {}", target.display()))?;
    use std::os::unix::fs::PermissionsExt;
    let mut perms = std::fs::metadata(target)?.permissions();
    perms.set_mode(0o755);
    std::fs::set_permissions(target, perms)?;
    Ok(())
}

fn accept_loop(listener: UnixListener, shutdown: Arc<AtomicBool>) {
    while !shutdown.load(Ordering::Acquire) {
        match listener.accept() {
            Ok((conn, _)) => {
                // A connection used purely to wake us during shutdown arrives
                // after the flag is set; bail before spawning a handler.
                if shutdown.load(Ordering::Acquire) {
                    break;
                }
                thread::spawn(move || handle_connection(conn));
            }
            Err(_) => break,
        }
    }
}

struct Control {
    cwd: String,
    pty: bool,
    env: Vec<(String, String)>,
    argv: Vec<String>,
}

fn handle_connection(mut conn: UnixStream) {
    // A woken-during-shutdown connection reads as EOF immediately.
    let control = match read_control(&mut conn) {
        Ok(c) => c,
        Err(_) => return,
    };

    let mut cmd = Command::new("systemd-run");
    cmd.arg("--user")
        .arg("--wait")
        .arg("--quiet")
        .arg(if control.pty { "--pty" } else { "--pipe" });
    if !control.cwd.is_empty() {
        cmd.arg("--working-directory").arg(&control.cwd);
    }
    for (k, v) in &control.env {
        cmd.arg("--setenv").arg(format!("{k}={v}"));
    }
    cmd.arg("--").args(&control.argv);

    cmd.stdin(Stdio::piped()).stdout(Stdio::piped());
    if !control.pty {
        cmd.stderr(Stdio::piped());
    }

    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("shellbox host-exec: failed to run systemd-run: {e}");
            let _ = write_frame(&mut conn, CH_EXIT, &127u32.to_le_bytes());
            return;
        }
    };

    // Split the stream into a dedicated read half (stdin pump, single reader)
    // and a shared, mutex-guarded write half (stdout/stderr/exit pumps).
    let write_half = match conn.try_clone() {
        Ok(c) => Arc::new(Mutex::new(c)),
        Err(_) => return,
    };

    let stdout = child.stdout.take();
    let pty = control.pty;
    let out_handle = {
        let w = write_half.clone();
        thread::spawn(move || pump_out(stdout, w, CH_STDOUT))
    };
    let err_handle = if !pty {
        let w = write_half.clone();
        let stderr = child.stderr.take();
        Some(thread::spawn(move || pump_out(stderr, w, CH_STDERR)))
    } else {
        None
    };

    // Forward inbound stdin frames (helper → command) in its own thread. The
    // main thread must be free to `child.wait()` and send the exit frame, so
    // this MUST NOT be inline: for a non-interactive command the helper never
    // sends a stdin frame (it's blocked on its own terminal stdin), and an
    // inline read would deadlock the whole handler.
    let in_handle = {
        let mut stdin = child.stdin.take();
        thread::spawn(move || {
            let mut hdr = [0u8; 5];
            loop {
                if read_exact(&mut conn, &mut hdr).is_err() {
                    break; // helper closed / died
                }
                let channel = hdr[0];
                let len = u32::from_le_bytes([hdr[1], hdr[2], hdr[3], hdr[4]]) as usize;
                if channel == CH_STDIN {
                    if len == 0 {
                        break; // EOF: drop stdin below to signal the command.
                    } else {
                        let mut data = vec![0u8; len];
                        if read_exact(&mut conn, &mut data).is_err() {
                            break;
                        }
                        if let Some(s) = stdin.as_mut() {
                            let _ = s.write_all(&data);
                        }
                    }
                } else {
                    // Unexpected inbound channel: skip its payload to stay framed.
                    let mut skip = vec![0u8; len];
                    let _ = read_exact(&mut conn, &mut skip);
                }
            }
            // Drop the command's stdin so any reader sees EOF, then exit.
            drop(stdin);
        })
    };

    // Main thread: wait for the command, then tell the helper to exit.
    let status = child.wait();
    let _ = out_handle.join();
    if let Some(h) = err_handle {
        let _ = h.join();
    }

    let code = status
        .ok()
        .and_then(|s| s.code())
        .unwrap_or(1) as u32;

    {
        let Ok(mut w) = write_half.lock() else { return };
        let _ = write_frame(&mut w, CH_EXIT, &code.to_le_bytes());
    }
    // The helper receives CH_EXIT → exits → closes the socket, which unblocks
    // the stdin thread's read. Join it so the connection is fully torn down.
    let _ = in_handle.join();
}

/// Read from a child output pipe and forward each chunk as a framed write to
/// the shared socket write half.
fn pump_out<R: Read>(mut out: Option<R>, write: Arc<Mutex<UnixStream>>, channel: u8) {
    let Some(out) = out.as_mut() else { return };
    let mut buf = [0u8; 16 * 1024];
    loop {
        match out.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => {
                let Ok(mut w) = write.lock() else { return };
                if write_frame(&mut w, channel, &buf[..n]).is_err() {
                    return;
                }
            }
            Err(_) => break,
        }
    }
}

// --- protocol I/O ----------------------------------------------------------

fn read_exact(stream: &mut UnixStream, buf: &mut [u8]) -> std::io::Result<()> {
    stream.read_exact(buf)
}

fn read_u32(stream: &mut UnixStream) -> std::io::Result<u32> {
    let mut buf = [0u8; 4];
    stream.read_exact(&mut buf)?;
    Ok(u32::from_le_bytes(buf))
}

fn read_string(stream: &mut UnixStream) -> std::io::Result<String> {
    let len = read_u32(stream)? as usize;
    let mut buf = vec![0u8; len];
    stream.read_exact(&mut buf)?;
    Ok(String::from_utf8_lossy(&buf).into_owned())
}

fn read_control(stream: &mut UnixStream) -> std::io::Result<Control> {
    let cwd = read_string(stream)?;
    let pty = read_u32(stream)? != 0;
    let n_env = read_u32(stream)? as usize;
    let mut env = Vec::with_capacity(n_env);
    for _ in 0..n_env {
        let k = read_string(stream)?;
        let v = read_string(stream)?;
        env.push((k, v));
    }
    let n_argv = read_u32(stream)? as usize;
    let mut argv = Vec::with_capacity(n_argv);
    for _ in 0..n_argv {
        argv.push(read_string(stream)?);
    }
    Ok(Control { cwd, pty, env, argv })
}

fn write_frame(stream: &mut UnixStream, channel: u8, data: &[u8]) -> std::io::Result<()> {
    let mut hdr = [0u8; 5];
    hdr[0] = channel;
    hdr[1..5].copy_from_slice(&(data.len() as u32).to_le_bytes());
    stream.write_all(&hdr)?;
    stream.write_all(data)?;
    Ok(())
}

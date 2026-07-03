//! `shellbox-host-exec` — the in-box half of shellbox's host-exec bridge.
//!
//! Installed alongside `shellbox` and bind-mounted into a box at
//! `/run/shellbox-host-exec`. Per-tool wrappers under `/run/shellbox-host-bin`
//! exec this binary with the tool name as the first argument:
//!
//!     /run/shellbox-host-exec podman ps -a
//!
//! It connects to the parent `shellbox` process's session socket (path in
//! `$SHELLBOX_HOST_EXEC_SOCK`), sends the command, then streams stdio
//! bidirectionally until the parent returns an exit code.
//!
//! Wire protocol — see `src/host_exec.rs` in the `shellbox` crate for the
//! authoritative definition. Both sides are kept in sync by hand.

use std::io::{IsTerminal, Read, Write};
use std::os::unix::net::UnixStream;
use std::process::exit;

const CH_STDIN: u8 = 0;
const CH_STDOUT: u8 = 1;
const CH_STDERR: u8 = 2;
const CH_EXIT: u8 = 0xFF;
const SOCK_ENV: &str = "SHELLBOX_HOST_EXEC_SOCK";

fn main() {
    let code = run();
    // Exiting here terminates the detached stdin-pump thread (which may be
    // blocked on a read). That is intended: the session ends with the command.
    exit(code);
}

fn run() -> i32 {
    // argv = [helper, tool, args...]
    let argv: Vec<String> = std::env::args().collect();
    if argv.len() < 2 {
        eprintln!("shellbox-host-exec: missing tool name");
        return 127;
    }
    let host_argv = &argv[1..];

    let sock_path = match std::env::var(SOCK_ENV) {
        Ok(p) => p,
        Err(_) => {
            eprintln!("shellbox-host-exec: ${SOCK_ENV} is not set");
            return 127;
        }
    };

    let mut conn = match UnixStream::connect(&sock_path) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("shellbox-host-exec: failed to connect to {sock_path}: {e}");
            return 127;
        }
    };

    let cwd = std::env::current_dir()
        .map(|p| p.display().to_string())
        .unwrap_or_default();
    let pty = std::io::stdout().is_terminal();
    // systemd-run starts with a clean environment; pass through only TERM so
    // color/line discipline survive. The host tool inherits the host's own
    // environment for everything else, which is what we want (e.g. podman's
    // config lives on the host).
    let env: Vec<(String, String)> = std::env::var("TERM")
        .ok()
        .map(|v| ("TERM".to_string(), v))
        .into_iter()
        .collect();

    if write_control(&mut conn, &cwd, pty, &env, host_argv).is_err() {
        eprintln!("shellbox-host-exec: failed to send command to host");
        return 127;
    }

    // Duplicate the socket so the stdin pump can write while the reader loop
    // (this thread) reads. Unix stream sockets are full-duplex.
    let write_half = match conn.try_clone() {
        Ok(c) => c,
        Err(_) => return 127,
    };
    // Detached: we never join it (it may block on stdin forever on a tty).
    std::thread::spawn(move || pump_stdin(write_half));

    read_loop(conn)
}

/// Forward local stdin to the parent as channel-0 frames; on EOF, send an
/// empty frame so the parent closes the command's stdin.
fn pump_stdin(mut conn: UnixStream) {
    let stdin = std::io::stdin();
    let mut lock = stdin.lock();
    let mut buf = [0u8; 16 * 1024];
    loop {
        match lock.read(&mut buf) {
            Ok(0) => {
                let _ = write_frame(&mut conn, CH_STDIN, &[]);
                break;
            }
            Ok(n) => {
                if write_frame(&mut conn, CH_STDIN, &buf[..n]).is_err() {
                    break;
                }
            }
            Err(_) => break,
        }
    }
}

/// Read frames from the parent and dispatch them to stdout/stderr, until an
/// exit frame arrives. Returns the exit code.
fn read_loop(mut conn: UnixStream) -> i32 {
    let mut hdr = [0u8; 5];
    loop {
        if read_exact(&mut conn, &mut hdr).is_err() {
            return 1; // socket closed without an exit frame
        }
        let channel = hdr[0];
        let len = u32::from_le_bytes([hdr[1], hdr[2], hdr[3], hdr[4]]) as usize;
        match channel {
            CH_STDOUT => {
                if copy_out(&mut conn, len, std::io::stdout()).is_err() {
                    return 1;
                }
            }
            CH_STDERR => {
                if copy_out(&mut conn, len, std::io::stderr()).is_err() {
                    return 1;
                }
            }
            CH_EXIT => {
                let mut buf = [0u8; 4];
                if len == 4 && read_exact(&mut conn, &mut buf).is_ok() {
                    return u32::from_le_bytes(buf) as i32;
                }
                return 1;
            }
            _ => {
                // Unknown channel: skip its payload to stay framed.
                let mut skip = vec![0u8; len];
                let _ = read_exact(&mut conn, &mut skip);
            }
        }
    }
}

fn copy_out(conn: &mut UnixStream, len: usize, mut out: impl Write) -> std::io::Result<()> {
    let mut remaining = len;
    let mut buf = [0u8; 16 * 1024];
    while remaining > 0 {
        let n = std::cmp::min(remaining, buf.len());
        conn.read_exact(&mut buf[..n])?;
        out.write_all(&buf[..n])?;
        remaining -= n;
    }
    Ok(())
}

fn write_control(
    conn: &mut UnixStream,
    cwd: &str,
    pty: bool,
    env: &[(String, String)],
    argv: &[String],
) -> std::io::Result<()> {
    write_bytes(conn, cwd.as_bytes())?;
    conn.write_all(&(pty as u32).to_le_bytes())?;
    conn.write_all(&(env.len() as u32).to_le_bytes())?;
    for (k, v) in env {
        write_bytes(conn, k.as_bytes())?;
        write_bytes(conn, v.as_bytes())?;
    }
    conn.write_all(&(argv.len() as u32).to_le_bytes())?;
    for a in argv {
        write_bytes(conn, a.as_bytes())?;
    }
    Ok(())
}

fn write_bytes(conn: &mut UnixStream, b: &[u8]) -> std::io::Result<()> {
    conn.write_all(&(b.len() as u32).to_le_bytes())?;
    conn.write_all(b)?;
    Ok(())
}

fn write_frame(conn: &mut UnixStream, channel: u8, data: &[u8]) -> std::io::Result<()> {
    let mut hdr = [0u8; 5];
    hdr[0] = channel;
    hdr[1..5].copy_from_slice(&(data.len() as u32).to_le_bytes());
    conn.write_all(&hdr)?;
    conn.write_all(data)?;
    Ok(())
}

fn read_exact(conn: &mut UnixStream, buf: &mut [u8]) -> std::io::Result<()> {
    conn.read_exact(buf)
}

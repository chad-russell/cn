//! Rootless composefs-via-FUSE runtime.
//!
//! A box runs entirely rootlessly: shellbox mounts the composefs image through
//! FUSE inside a private user + mount namespace. No `sudo`, no persistent host
//! mount: the FUSE mount lives only for the duration of the command and dies
//! with the process.
//!
//! # Lifecycle (all in the shellbox process)
//!
//! 1. `unshare(CLONE_NEWUSER | CLONE_NEWNS)` — private namespaces. We use an
//!    *identity* uid map (`<uid> <uid> 1`) so that file ownership presents as
//!    the real user (your files are yours; root-owned system files show as
//!    nobody but stay world-readable). The namespace creator retains the
//!    privileges needed to mount within it.
//! 2. Open `/dev/fuse`, `fsopen`/`fsconfig`/`fsmount` a FUSE filesystem with
//!    `user_id = <real uid>` (the upstream `mount_fuse` hardcodes 0, which
//!    would invert ownership under an identity map — hence our own mount fn),
//!    and `move_mount` it onto a private tempdir mountpoint.
//! 3. Spawn a thread running `serve_tree_fuse` (see `treefuse.rs`) against the
//!    parsed image. This thread answers all FUSE requests for the mount's
//!    lifetime.
//! 4. Build & spawn the bwrap command against the FUSE mountpoint as `/`, and
//!    wait for it.
//! 5. On exit: `umount` the mountpoint (this terminates the FUSE session,
//!    unblocking the server thread), join the thread, and return bwrap's exit
//!    status.

mod treefuse;

use std::fs;
use std::os::fd::{AsFd, AsRawFd, OwnedFd};
use std::path::Path;
use std::process::Command;

use anyhow::{Context, Result};
use rustix::fd::BorrowedFd;
use rustix::fs::{Mode, OFlags};
use rustix::mount::{
    FsMountFlags, MoveMountFlags, fsconfig_create, fsconfig_set_flag, fsconfig_set_string, fsmount,
    move_mount,
};
use rustix::thread::{UnshareFlags, unshare_unsafe};
use tempfile::TempDir;

use composefs::erofs::reader::erofs_to_filesystem;
use composefs::fsverity::Sha256HashValue;
use composefs::mount::FsHandle;
use composefs::repository::{RepoMetadata, Repository};

use treefuse::serve_tree_fuse;

/// Run a command inside a rootless FUSE-backed composefs mount.
///
/// `store` is the content-addressed object store (`mkcomposefs --digest-store`
/// output). `build_bwrap` is given the FUSE mountpoint path (inside the private
/// namespace) and must return the fully-configured bwrap `Command`.
pub fn run_rootless<F>(
    image: &Path,
    store: &Path,
    build_bwrap: F,
) -> Result<std::process::ExitStatus>
where
    F: FnOnce(&Path) -> Command,
{
    // Snapshot real uid/gid BEFORE entering the user namespace.
    let uid = nix::unistd::getuid().as_raw();
    let gid = nix::unistd::getgid().as_raw();

    // 1. Private user + mount namespaces. The new mount namespace is owned by
    //    the new user namespace, so mounts here are invisible to the host and
    //    auto-cleaned when the namespace dies.
    // SAFETY: We do not use `UnshareFlags::FILES`, so the FD-table hazard
    // documented on `unshare_unsafe` does not apply. NEWUSER+NEWNS only.
    unsafe {
        unshare_unsafe(UnshareFlags::NEWUSER | UnshareFlags::NEWNS).context(
            "unshare(CLONE_NEWUSER | CLONE_NEWNS) failed — is unprivileged userns allowed?",
        )?;
    }

    // Identity mapping: <real uid> <real uid> 1 (see module docs).
    write_uid_map(uid, gid)?;

    // 2. Parse the image and open the object store as a composefs repository.
    let image_data =
        fs::read(image).with_context(|| format!("reading composefs image {}", image.display()))?;
    let filesystem = erofs_to_filesystem::<Sha256HashValue>(&image_data)
        .context("parsing composefs image into a filesystem tree")?;
    let repo = open_repo(store)?;

    // Private mountpoint inside this namespace.
    let mnt_tmp = TempDir::new().context("creating FUSE mountpoint tempdir")?;
    let mountpoint = mnt_tmp.path();

    let dev_fuse = open_fuse().context("opening /dev/fuse")?;
    mount_fuse_at(dev_fuse.as_fd(), mountpoint, uid, gid)
        .with_context(|| format!("mounting composefs-fuse at {}", mountpoint.display()))?;

    // 3. Serve FUSE in a background thread. It owns dev_fuse / filesystem /
    //    repo for the session's lifetime.
    let server = std::thread::Builder::new()
        .name("shellbox-fuse".into())
        .spawn({
            let fs = filesystem;
            let repo = repo;
            move || {
                if let Err(e) = serve_tree_fuse(dev_fuse, &fs, &repo) {
                    // The session ends normally with a benign error when the
                    // mount is torn down; only surface real failures.
                    let msg = e.to_string();
                    if !is_benign_teardown(&msg) {
                        eprintln!("shellbox-fuse server exited: {e}");
                    }
                }
            }
        })
        .context("spawning FUSE server thread")?;

    // 4. Run bwrap against the FUSE mountpoint.
    let mut bwrap = build_bwrap(mountpoint);
    let status = bwrap.status().context("spawning bwrap")?;

    // 5. Tear down: umount ends the FUSE session → server thread returns.
    let _ = rustix::mount::unmount(mountpoint, rustix::mount::UnmountFlags::empty());
    let _ = server.join();

    Ok(status)
}

fn is_benign_teardown(msg: &str) -> bool {
    // fuser/the kernel report these when the mount is umounted out from under
    // the session; that's the expected shutdown path, not an error.
    msg.contains("ENOTCONN")
        || msg.contains("ECONNRESET")
        || msg.contains("end of file")
        || msg.contains("Unexpected EOF")
        || msg.contains("Connection")
}

/// Write identity uid_map / setgroups / gid_map for the current process (which
/// must just have called `unshare(CLONE_NEWUSER)`).
fn write_uid_map(uid: u32, gid: u32) -> Result<()> {
    // gid_map requires denying setgroups first for unprivileged mappings.
    fs::write("/proc/self/setgroups", "deny").context("writing /proc/self/setgroups")?;
    fs::write("/proc/self/uid_map", format!("{uid} {uid} 1\n"))
        .context("writing /proc/self/uid_map")?;
    fs::write("/proc/self/gid_map", format!("{gid} {gid} 1\n"))
        .context("writing /proc/self/gid_map")?;
    Ok(())
}

/// Open a composefs object store as a Repository, in insecure mode (mkcomposefs
/// objects may lack fs-verity; we don't require it for local trusted images).
/// Bridges the layout: mkcomposefs writes `store/XX/...`, composefs-rs expects
/// `<repo>/objects/XX/...`. We write a minimal `meta.json` ourselves so we can
/// use plain `open_path` (rather than `open_upgrade`, which tries to write
/// meta.json from inside the post-unshare namespace where the write can fail).
fn open_repo(store: &Path) -> Result<Repository<Sha256HashValue>> {
    // Adapter dir: a real directory (writable, so we can place meta.json) whose
    // `objects/` is a symlink to the actual mkcomposefs store.
    let adapter = TempDir::new().context("creating repository adapter dir")?;
    let link = adapter.path().join("objects");
    std::os::unix::fs::symlink(store, &link)
        .with_context(|| format!("symlinking {} -> {}", link.display(), store.display()))?;

    // Write a minimal meta.json: sha256 algorithm, no verity. mkcomposefs's
    // --digest-store doesn't carry meta.json, and we force insecure anyway.
    let meta = RepoMetadata::for_hash::<Sha256HashValue>();
    let meta_json = serde_json::to_vec_pretty(&meta).context("serializing repo meta.json")?;
    std::fs::write(adapter.path().join("meta.json"), meta_json)
        .context("writing adapter meta.json")?;

    let repo_fd = rustix::fs::open(
        adapter.path(),
        OFlags::RDONLY | OFlags::DIRECTORY | OFlags::CLOEXEC,
        Mode::empty(),
    )
    .with_context(|| format!("opening adapter repo dir {}", adapter.path().display()))?;

    let mut repo = Repository::<Sha256HashValue>::open_path(repo_fd, ".")
        .map_err(|e| anyhow::anyhow!("opening composefs repository: {e}"))?;
    // mkcomposefs objects may or may not carry fs-verity; force insecure so
    // reads never require it.
    repo.set_insecure();

    // Leak the adapter TempDir: the repo holds an fd into it for the session.
    // It's tiny (one symlink + one small json) and lives only as long as the
    // process / namespace.
    std::mem::forget(adapter);
    Ok(repo)
}

fn open_fuse() -> Result<OwnedFd> {
    rustix::fs::open("/dev/fuse", OFlags::RDWR | OFlags::CLOEXEC, Mode::empty())
        .context("Unable to open /dev/fuse — is FUSE available?")
}

/// Mount a FUSE filesystem backed by `dev_fuse` at `mountpoint`, configured for
/// composefs, owned by `uid`/`gid` (the real user, per the identity map).
fn mount_fuse_at(dev_fuse: BorrowedFd<'_>, mountpoint: &Path, uid: u32, gid: u32) -> Result<()> {
    let mnt_dirfd = rustix::fs::open(
        mountpoint,
        OFlags::RDONLY | OFlags::DIRECTORY | OFlags::CLOEXEC,
        Mode::empty(),
    )
    .with_context(|| format!("opening mountpoint {}", mountpoint.display()))?;

    let fusefs = FsHandle::open("fuse").context("fsopen(\"fuse\")")?;
    let fd = fusefs.as_fd();
    let uid_s = uid.to_string();
    let gid_s = gid.to_string();
    let dev_fd_s = dev_fuse.as_raw_fd().to_string();
    fsconfig_set_flag(fd, "ro")?;
    fsconfig_set_flag(fd, "default_permissions")?;
    fsconfig_set_string(fd, "source", "shellbox-composefs-fuse")?;
    fsconfig_set_string(fd, "rootmode", "040555")?;
    fsconfig_set_string(fd, "user_id", &uid_s)?;
    fsconfig_set_string(fd, "group_id", &gid_s)?;
    fsconfig_set_string(fd, "fd", &dev_fd_s)?;
    fsconfig_create(fd)?;

    let mnt = fsmount(
        fd,
        FsMountFlags::FSMOUNT_CLOEXEC,
        rustix::mount::MountAttrFlags::empty(),
    )?;

    // Attach the (otherwise detached) mount to the mountpoint path.
    move_mount(
        mnt.as_fd(),
        "",
        mnt_dirfd.as_fd(),
        "",
        MoveMountFlags::MOVE_MOUNT_F_EMPTY_PATH | MoveMountFlags::MOVE_MOUNT_T_EMPTY_PATH,
    )?;
    Ok(())
}

//! Rootless composefs-via-FUSE runtime.
//!
//! When a box is prepared but not (kernel-)mounted, shellbox can run it fully
//! rootlessly by mounting the composefs image through FUSE inside a private
//! user + mount namespace. No `sudo`, no persistent host mount: the FUSE mount
//! lives only for the duration of the command and dies with the process.
//!
//! # Lifecycle (all in the shellbox process)
//!
//! 1. `unshare(CLONE_NEWUSER | CLONE_NEWNS)` — private namespaces. We use an
//!    *identity* uid map (`<uid> <uid> 1`) so that file ownership presents
//!    identically to the kernel-mount path (your files are yours; root-owned
//!    system files show as nobody but stay world-readable). The namespace
//!    creator retains the privileges needed to mount within it.
//! 2. Open `/dev/fuse`, `fsopen`/`fsconfig`/`fsmount` a FUSE filesystem with
//!    `user_id = <real uid>` (the upstream `mount_fuse` hardcodes 0, which
//!    would invert ownership under an identity map — hence our own mount fn),
//!    and `move_mount` it onto a private tempdir mountpoint.
//! 3. Spawn a thread running `serve_tree_fuse` against the parsed image. This
//!    thread answers all FUSE requests for the mount's lifetime.
//! 4. Build & spawn the bwrap command (same args as the kernel path) against
//!    the FUSE mountpoint as `/`, and wait for it.
//! 5. On exit: `umount` the mountpoint (this terminates the FUSE session,
//!    unblocking the server thread), join the thread, and return bwrap's
//!    exit status.
//!
//! The TreeFuse implementation is vendored from composefs-fuse (MIT OR
//! Apache-2.0), concretely typed for Sha256HashValue, with `readdirplus`
//! added (the key metadata optimization for stat-heavy workloads).

use std::collections::HashMap;
use std::ffi::OsStr;
use std::fs;
use std::os::fd::{AsFd, AsRawFd, OwnedFd};
use std::os::unix::ffi::OsStrExt;
use std::path::Path;
use std::process::Command;
use std::time::{Duration, SystemTime};

use anyhow::{Context, Result};
use rustix::fd::BorrowedFd;
use rustix::fs::{Mode, OFlags};
use rustix::mount::{
    fsmount, fsconfig_create, fsconfig_set_flag, fsconfig_set_string, move_mount,
    FsMountFlags, MoveMountFlags,
};
use rustix::thread::{unshare_unsafe, UnshareFlags};
use tempfile::TempDir;

use composefs::erofs::reader::erofs_to_filesystem;
use composefs::fsverity::Sha256HashValue;
use composefs::mount::FsHandle;
use composefs::repository::{Repository, RepoMetadata};

use fuser::{
    FileAttr, FileType, Filesystem, ReplyAttr, ReplyData, ReplyDirectory, ReplyDirectoryPlus,
    ReplyEntry, ReplyOpen, Request, Session, SessionACL,
};
use rustix::buffer::spare_capacity;
use rustix::io::{pread, Errno};

// ===========================================================================
// public entry point
// ===========================================================================

/// Run a command inside a rootless FUSE-backed composefs mount.
///
/// `store` is the content-addressed object store (`mkcomposefs --digest-store`
/// output). `build_bwrap` is given the FUSE mountpoint path (inside the
/// private namespace) and must return the fully-configured bwrap `Command`;
/// the caller reuses the exact same builder as the kernel-mount path so the
/// two are identical except for the root.
///
/// `host_tools` are the box's `[host]` tool names. When non-empty, the
/// `HostExecSession` is started **after** `unshare(CLONE_NEWUSER|CLONE_NEWNS)`,
/// because `CLONE_NEWNS` is rejected (`EINVAL`) if the caller is multithreaded
/// — and the session spawns an accept thread. The session is then handed to the
/// bwrap builder so its binds/env get wired in, and torn down before FUSE.
pub fn run_rootless<F>(
    image: &Path,
    store: &Path,
    host_tools: &[String],
    build_bwrap: F,
) -> Result<std::process::ExitStatus>
where
    F: FnOnce(&Path, Option<&crate::host_exec::HostExecSession>) -> Command,
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
        unshare_unsafe(UnshareFlags::NEWUSER | UnshareFlags::NEWNS)
            .context("unshare(CLONE_NEWUSER | CLONE_NEWNS) failed — is unprivileged userns allowed?")?;
    }

    // Identity mapping: <real uid> <real uid> 1. This keeps file ownership
    // presentation identical to the kernel-mount path (see module docs).
    write_uid_map(uid, gid)?;

    // 2. Parse the image and open the object store as a composefs repository.
    let image_data = fs::read(image)
        .with_context(|| format!("reading composefs image {}", image.display()))?;
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

    // Start the host-exec session (if the box declares [host] tools) AFTER
    // unshare: CLONE_NEWNS above requires a single-threaded caller, and the
    // session spawns an accept thread. Running from this identity-mapped child
    // user namespace is fine — systemd --user authenticates by uid, which the
    // identity map preserves, so `systemd-run --user` from handlers reaches
    // the host user manager normally (same model as flatpak-spawn/toolbox).
    let host_session = if host_tools.is_empty() {
        None
    } else {
        Some(crate::host_exec::HostExecSession::start(host_tools)?)
    };

    // 4. Run bwrap against the FUSE mountpoint.
    let mut bwrap = build_bwrap(mountpoint, host_session.as_ref());
    let status = bwrap.status().context("spawning bwrap")?;

    // Stop the host-exec server before tearing the FUSE mount down.
    drop(host_session);

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

// ===========================================================================
// namespace + mount plumbing
// ===========================================================================

/// Write identity uid_map / setgroups / gid_map for the current process (which
/// must just have called `unshare(CLONE_NEWUSER)`).
fn write_uid_map(uid: u32, gid: u32) -> Result<()> {
    // gid_map requires denying setgroups first for unprivileged mappings.
    fs::write("/proc/self/setgroups", "deny")
        .context("writing /proc/self/setgroups")?;
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
fn mount_fuse_at(
    dev_fuse: BorrowedFd<'_>,
    mountpoint: &Path,
    uid: u32,
    gid: u32,
) -> Result<()> {
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

    let mnt = fsmount(fd, FsMountFlags::FSMOUNT_CLOEXEC, rustix::mount::MountAttrFlags::empty())?;

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

// ===========================================================================
// vendored TreeFuse (composefs-fuse, MIT OR Apache-2.0) + readdirplus
// ===========================================================================

const TTL: Duration = Duration::from_secs(1_000_000);
type Ino = u64;

#[derive(Debug)]
struct InodeMap {
    dir_inos: HashMap<*const Directory<Sha256HashValue>, Ino>,
    leaf_inos: Vec<Ino>,
}

impl InodeMap {
    fn build(fs: &composefs::tree::FileSystem<Sha256HashValue>) -> Self {
        use composefs::tree::Inode;
        let mut next_ino: Ino = 1;
        let mut dir_inos = HashMap::new();
        let mut leaf_inos = vec![0u64; fs.leaves.len()];

        fn walk(
            dir: &Directory<Sha256HashValue>,
            next_ino: &mut Ino,
            dir_inos: &mut HashMap<*const Directory<Sha256HashValue>, Ino>,
            leaf_inos: &mut [Ino],
        ) {
            let ino = *next_ino;
            *next_ino += 1;
            dir_inos.insert(dir as *const _, ino);
            for (_, inode) in dir.entries() {
                match inode {
                    Inode::Directory(subdir) => walk(subdir, next_ino, dir_inos, leaf_inos),
                    Inode::Leaf(id, _) => {
                        if leaf_inos[id.0] == 0 {
                            leaf_inos[id.0] = *next_ino;
                            *next_ino += 1;
                        }
                    }
                }
            }
        }
        walk(&fs.root, &mut next_ino, &mut dir_inos, &mut leaf_inos);
        InodeMap { dir_inos, leaf_inos }
    }

    fn dir_ino(&self, dir: &Directory<Sha256HashValue>) -> Ino {
        self.dir_inos[&(dir as *const _)]
    }
    fn leaf_ino(&self, id: composefs::generic_tree::LeafId) -> Ino {
        self.leaf_inos[id.0]
    }
    fn inode_ino(&self, inode: &composefs::tree::Inode<Sha256HashValue>) -> Ino {
        match inode {
            composefs::tree::Inode::Directory(dir) => self.dir_ino(dir),
            composefs::tree::Inode::Leaf(id, _) => self.leaf_ino(*id),
        }
    }
}

#[derive(Debug, Clone)]
enum InodeRef<'a> {
    Directory(&'a Directory<Sha256HashValue>, Ino),
    Leaf(composefs::generic_tree::LeafId, &'a composefs::tree::Leaf<Sha256HashValue>),
}

use composefs::tree::{Directory, FileSystem, Inode, LeafContent, RegularFile, Stat};

impl<'a> InodeRef<'a> {
    fn nlink(&self, nlink_map: &[u32]) -> u32 {
        (match self {
            InodeRef::Directory(dir, ..) => {
                2 + dir
                    .inodes()
                    .filter(|i| matches!(i, Inode::Directory(..)))
                    .count()
            }
            InodeRef::Leaf(leaf_id, _) => nlink_map[leaf_id.0] as usize,
        }) as u32
    }
    fn rdev(&self) -> u32 {
        (match self {
            InodeRef::Directory(..) => 0,
            InodeRef::Leaf(_, leaf) => match &leaf.content {
                LeafContent::BlockDevice(rdev) | LeafContent::CharacterDevice(rdev) => *rdev,
                _ => 0,
            },
        }) as u32
    }
    fn kind(&self) -> FileType {
        match self {
            InodeRef::Directory(..) => FileType::Directory,
            InodeRef::Leaf(_, leaf) => match leaf.content {
                LeafContent::BlockDevice(..) => FileType::BlockDevice,
                LeafContent::CharacterDevice(..) => FileType::CharDevice,
                LeafContent::Fifo => FileType::NamedPipe,
                LeafContent::Regular(..) => FileType::RegularFile,
                LeafContent::Socket => FileType::Socket,
                LeafContent::Symlink(..) => FileType::Symlink,
            },
        }
    }
    fn stat(&self) -> &'a Stat {
        match self {
            InodeRef::Directory(dir, ..) => &dir.stat,
            InodeRef::Leaf(_, leaf) => &leaf.stat,
        }
    }
    fn size(&self) -> u64 {
        match self {
            InodeRef::Directory(..) => 0,
            InodeRef::Leaf(_, leaf) => match &leaf.content {
                LeafContent::Regular(RegularFile::Inline(data)) => data.len() as u64,
                LeafContent::Regular(RegularFile::External(.., size)) => *size,
                _ => 0,
            },
        }
    }
    fn fileattr(&self, ino: Ino, nlink_map: &[u32]) -> FileAttr {
        let stat = self.stat();
        let mtime = SystemTime::UNIX_EPOCH + Duration::from_secs(stat.st_mtim_sec as u64);
        FileAttr {
            ino,
            size: self.size(),
            blocks: 1,
            atime: mtime,
            mtime,
            ctime: mtime,
            crtime: mtime,
            kind: self.kind(),
            perm: stat.st_mode as u16,
            nlink: self.nlink(nlink_map),
            uid: stat.st_uid,
            gid: stat.st_gid,
            rdev: self.rdev(),
            blksize: 4096,
            flags: 0,
        }
    }
}

#[derive(Debug)]
enum OpenHandle {
    Fd(OwnedFd),
    Data(Box<[u8]>),
}

#[derive(Debug)]
struct TreeFuse<'a> {
    repo: &'a Repository<Sha256HashValue>,
    fs: &'a FileSystem<Sha256HashValue>,
    inode_map: InodeMap,
    nlink_map: Vec<u32>,
    inodes: HashMap<Ino, InodeRef<'a>>,
    attrs: HashMap<Ino, FileAttr>,
    handles: HashMap<u64, OpenHandle>,
    next_fh: u64,
}

impl<'a> TreeFuse<'a> {
    fn register_inode(&mut self, inode: &'a Inode<Sha256HashValue>, parent: Ino) -> (Ino, FileType) {
        let ino = self.inode_map.inode_ino(inode);
        let iref = match inode {
            Inode::Directory(dir) => InodeRef::Directory(dir, parent),
            Inode::Leaf(leaf_id, _) => InodeRef::Leaf(*leaf_id, self.fs.leaf(*leaf_id)),
        };
        let kind = iref.kind();
        self.attrs.insert(ino, iref.fileattr(ino, &self.nlink_map));
        self.inodes.insert(ino, iref);
        (ino, kind)
    }
}

impl Filesystem for TreeFuse<'_> {
    fn statfs(&mut self, _req: &Request<'_>, _ino: u64, reply: fuser::ReplyStatfs) {
        reply.statfs(0, 0, 0, 0, 0, 4096, 255, 4096);
    }

    fn lookup(&mut self, _req: &Request, parent: u64, name: &OsStr, reply: ReplyEntry) {
        let Some(InodeRef::Directory(dir, ..)) = self.inodes.get(&parent) else {
            return reply.error(Errno::BADF.raw_os_error());
        };
        let dir = *dir;
        match dir.lookup(name) {
            Some(inode) => {
                let (ino, _) = self.register_inode(inode, parent);
                reply.entry(&TTL, self.attrs.get(&ino).unwrap(), 0);
            }
            None => reply.error(Errno::NOENT.raw_os_error()),
        }
    }

    fn getattr(&mut self, _req: &Request, ino: u64, _fh: Option<u64>, reply: ReplyAttr) {
        if let Some(attrs) = self.attrs.get(&ino) {
            return reply.attr(&TTL, attrs);
        }
        let Some(iref) = self.inodes.get(&ino) else {
            return reply.error(Errno::BADF.raw_os_error());
        };
        let iref = iref.clone();
        let attr = iref.fileattr(ino, &self.nlink_map);
        self.attrs.insert(ino, attr);
        reply.attr(&TTL, self.attrs.get(&ino).unwrap());
    }

    fn readlink(&mut self, _req: &Request<'_>, ino: u64, reply: ReplyData) {
        let Some(InodeRef::Leaf(_, leaf)) = self.inodes.get(&ino) else {
            return reply.error(Errno::INVAL.raw_os_error());
        };
        let LeafContent::Symlink(target) = &leaf.content else {
            return reply.error(Errno::INVAL.raw_os_error());
        };
        reply.data(target.as_bytes());
    }

    fn opendir(&mut self, _req: &Request<'_>, _ino: u64, _flags: i32, reply: ReplyOpen) {
        reply.opened(0, 0);
    }

    fn readdir(
        &mut self,
        _req: &Request,
        ino: u64,
        _fh: u64,
        mut offset: i64,
        mut reply: ReplyDirectory,
    ) {
        let Some(InodeRef::Directory(dir, parent)) = self.inodes.get(&ino) else {
            return reply.error(Errno::BADF.raw_os_error());
        };
        let (dir, parent) = (*dir, *parent);
        if offset == 0 {
            offset += 1;
            if reply.add(ino, offset, FileType::Directory, ".") {
                return reply.ok();
            }
        }
        if offset == 1 {
            offset += 1;
            if reply.add(parent, offset, FileType::Directory, "..") {
                return reply.ok();
            }
        }
        for (name, inode) in dir.sorted_entries().skip(offset as usize - 2) {
            let (child_ino, kind) = self.register_inode(inode, ino);
            offset += 1;
            if reply.add(child_ino, offset, kind, name) {
                break;
            }
        }
        reply.ok();
    }

    /// readdirplus: combines directory listing with attribute return,
    /// eliminating a separate lookup/stat round-trip per file — the key
    /// optimization for stat-heavy workloads (find/du/grep).
    fn readdirplus(
        &mut self,
        _req: &Request,
        ino: u64,
        _fh: u64,
        mut offset: i64,
        mut reply: ReplyDirectoryPlus,
    ) {
        let Some(InodeRef::Directory(dir, parent)) = self.inodes.get(&ino) else {
            return reply.error(Errno::BADF.raw_os_error());
        };
        let (dir, parent) = (*dir, *parent);
        if offset == 0 {
            offset += 1;
            if let Some(attr) = self.attrs.get(&ino).cloned() {
                if reply.add(ino, offset, ".", &TTL, &attr, 0) {
                    return reply.ok();
                }
            }
        }
        if offset == 1 {
            offset += 1;
            if let Some(attr) = self.attrs.get(&parent).cloned() {
                if reply.add(parent, offset, "..", &TTL, &attr, 0) {
                    return reply.ok();
                }
            }
        }
        for (name, inode) in dir.sorted_entries().skip(offset as usize - 2) {
            let (child_ino, _) = self.register_inode(inode, ino);
            let attr = self.attrs.get(&child_ino).unwrap();
            offset += 1;
            if reply.add(child_ino, offset, name, &TTL, attr, 0) {
                break;
            }
        }
        reply.ok();
    }

    fn releasedir(
        &mut self,
        _req: &Request<'_>,
        _ino: u64,
        _fh: u64,
        _flags: i32,
        reply: fuser::ReplyEmpty,
    ) {
        reply.ok();
    }

    fn getxattr(
        &mut self,
        _req: &Request<'_>,
        ino: u64,
        name: &OsStr,
        size: u32,
        reply: fuser::ReplyXattr,
    ) {
        let Some(iref) = self.inodes.get(&ino) else {
            return reply.error(Errno::BADF.raw_os_error());
        };
        let xattrs = &iref.stat().xattrs;
        let Some(value) = xattrs.get(name) else {
            return reply.error(Errno::NODATA.raw_os_error());
        };
        if size == 0 {
            reply.size(value.len() as u32);
        } else if value.len() > size as usize {
            reply.error(Errno::RANGE.raw_os_error());
        } else {
            reply.data(value);
        }
    }

    fn listxattr(&mut self, _req: &Request<'_>, ino: u64, size: u32, reply: fuser::ReplyXattr) {
        let Some(iref) = self.inodes.get(&ino) else {
            return reply.error(Errno::BADF.raw_os_error());
        };
        let mut list = vec![];
        for name in iref.stat().xattrs.keys() {
            list.extend_from_slice(name.as_bytes());
            list.push(b'\0');
        }
        if size == 0 {
            reply.size(list.len() as u32);
        } else if list.len() > size as usize {
            reply.error(Errno::RANGE.raw_os_error());
        } else {
            reply.data(&list);
        }
    }

    fn open(&mut self, _req: &Request<'_>, ino: u64, _flags: i32, reply: ReplyOpen) {
        let Some(iref) = self.inodes.get(&ino) else {
            return reply.error(Errno::BADF.raw_os_error());
        };
        let InodeRef::Leaf(_, leaf) = iref else {
            return reply.error(Errno::BADF.raw_os_error());
        };
        let handle = match &leaf.content {
            LeafContent::Regular(RegularFile::External(id, ..)) => {
                let Ok(fd) = self.repo.open_object(id) else {
                    return reply.error(Errno::INVAL.raw_os_error());
                };
                OpenHandle::Fd(fd)
            }
            LeafContent::Regular(RegularFile::Inline(data)) => OpenHandle::Data(data.clone()),
            _ => return reply.error(Errno::BADF.raw_os_error()),
        };
        let fh = self.next_fh;
        self.next_fh += 1;
        self.handles.insert(fh, handle);
        reply.opened(fh, 0);
    }

    fn read(
        &mut self,
        _req: &Request<'_>,
        _ino: u64,
        fh: u64,
        offset: i64,
        size: u32,
        _flags: i32,
        _lock_owner: Option<u64>,
        reply: ReplyData,
    ) {
        match self.handles.get(&fh) {
            Some(OpenHandle::Fd(fd)) => {
                let mut data = Vec::with_capacity(size as usize);
                match pread(fd, spare_capacity(&mut data), offset as u64) {
                    Ok(_) => reply.data(&data),
                    Err(errno) => reply.error(errno.raw_os_error()),
                }
            }
            Some(OpenHandle::Data(data)) => {
                if offset as usize > data.len() {
                    reply.data(b"");
                } else {
                    let mut data = &data[offset as usize..];
                    if data.len() > size as usize {
                        data = &data[..size as usize];
                    }
                    reply.data(data);
                }
            }
            None => reply.error(Errno::BADF.raw_os_error()),
        }
    }

    fn release(
        &mut self,
        _req: &Request<'_>,
        _ino: u64,
        fh: u64,
        _flags: i32,
        _lock_owner: Option<u64>,
        _flush: bool,
        reply: fuser::ReplyEmpty,
    ) {
        match self.handles.remove(&fh) {
            Some(_) => reply.ok(),
            None => reply.error(Errno::BADF.raw_os_error()),
        }
    }
}

/// Serve the composefs tree via FUSE until the mount is torn down.
fn serve_tree_fuse(
    dev_fuse: OwnedFd,
    filesystem: &FileSystem<Sha256HashValue>,
    repo: &Repository<Sha256HashValue>,
) -> std::io::Result<()> {
    let inode_map = InodeMap::build(filesystem);
    let nlink_map = filesystem.nlinks();
    let root_ino = inode_map.dir_ino(&filesystem.root);
    let root_ref = InodeRef::Directory(&filesystem.root, root_ino);
    let root_attr = root_ref.fileattr(root_ino, &nlink_map);
    let tf = TreeFuse {
        repo,
        fs: filesystem,
        inode_map,
        nlink_map,
        inodes: HashMap::from([(root_ino, root_ref)]),
        attrs: HashMap::from([(root_ino, root_attr)]),
        handles: Default::default(),
        next_fh: 1,
    };
    Session::from_fd(tf, dev_fuse, SessionACL::All).run()
}

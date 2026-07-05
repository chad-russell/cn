//! Vendored TreeFuse filesystem (from composefs-fuse, MIT OR Apache-2.0),
//! concretely typed for `Sha256HashValue`, with `readdirplus` added (the key
//! metadata optimization for stat-heavy workloads like `find`/`du`/`grep`).
//!
//! This is the in-process FUSE `Filesystem` impl that `serve_tree_fuse` runs
//! against the parsed composefs tree. It is self-contained: the parent module
//! only calls `serve_tree_fuse(dev_fuse, &fs, &repo)`.

use std::collections::HashMap;
use std::ffi::OsStr;
use std::os::fd::OwnedFd;
use std::os::unix::ffi::OsStrExt;
use std::time::{Duration, SystemTime};

use composefs::fsverity::Sha256HashValue;
use composefs::repository::Repository;
use composefs::tree::{Directory, FileSystem, Inode, LeafContent, RegularFile, Stat};
use fuser::{
    FileAttr, FileType, Filesystem, ReplyAttr, ReplyData, ReplyDirectory, ReplyDirectoryPlus,
    ReplyEntry, ReplyOpen, Request, Session, SessionACL,
};
use rustix::buffer::spare_capacity;
use rustix::io::{Errno, pread};

const TTL: Duration = Duration::from_secs(1_000_000);
type Ino = u64;

#[derive(Debug)]
struct InodeMap {
    dir_inos: HashMap<*const Directory<Sha256HashValue>, Ino>,
    leaf_inos: Vec<Ino>,
}

impl InodeMap {
    fn build(fs: &FileSystem<Sha256HashValue>) -> Self {
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
        InodeMap {
            dir_inos,
            leaf_inos,
        }
    }

    fn dir_ino(&self, dir: &Directory<Sha256HashValue>) -> Ino {
        self.dir_inos[&(dir as *const _)]
    }
    fn leaf_ino(&self, id: composefs::generic_tree::LeafId) -> Ino {
        self.leaf_inos[id.0]
    }
    fn inode_ino(&self, inode: &Inode<Sha256HashValue>) -> Ino {
        match inode {
            Inode::Directory(dir) => self.dir_ino(dir),
            Inode::Leaf(id, _) => self.leaf_ino(*id),
        }
    }
}

#[derive(Debug, Clone)]
enum InodeRef<'a> {
    Directory(&'a Directory<Sha256HashValue>, Ino),
    Leaf(
        composefs::generic_tree::LeafId,
        &'a composefs::tree::Leaf<Sha256HashValue>,
    ),
}

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
    fn register_inode(
        &mut self,
        inode: &'a Inode<Sha256HashValue>,
        parent: Ino,
    ) -> (Ino, FileType) {
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
            if let Some(attr) = self.attrs.get(&ino).cloned()
                && reply.add(ino, offset, ".", &TTL, &attr, 0)
            {
                return reply.ok();
            }
        }
        if offset == 1 {
            offset += 1;
            if let Some(attr) = self.attrs.get(&parent).cloned()
                && reply.add(parent, offset, "..", &TTL, &attr, 0)
            {
                return reply.ok();
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
pub(super) fn serve_tree_fuse(
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

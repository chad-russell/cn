# A2 — NFS uid-mapping proof: container writes /mnt/photos as uid 991

**Task:** t_f720a52c · **Date:** 2026-09-06 · **Status:** VERIFIED
**Evidence:** `docs/immich-loop/evidence/a2-nfs.md` (same commit)

## Chosen mechanism — quadlet `User=991:993` + `GroupAdd=100,1000` (no userns)

The immich quadlets (phase B) will carry:

```ini
[Container]
User=991:993
GroupAdd=100,1000
Volume=/mnt/photos:/mnt/photos:rslave
```

which quadlet renders to exactly the flags proven in the demo:

```
--user 991:993 --group-add 100,1000 -v /mnt/photos/.loop-sandbox:/sandbox
```

This is the **jellyfin precedent extended with group adds** — not a new pattern.

## Why the uid problem exists at all

NFS here is pure pass-through identity:

- nas export (`hosts/nas/nfs-exports.nix:14`, confirmed live in `/etc/exports` on nas):

  ```
  /pool/photos  192.168.20.0/24(rw,no_subtree_check,no_root_squash,fsid=2)
  ```

- Client mount is NFSv4.2 `sec=sys` (numeric uid/gid on the wire), `rw`.
- `no_root_squash` + no `anonuid`/`all_squash` ⇒ **the server applies no id
  translation whatsoever**. Whatever uid the process on bees presents is what
  owns the file on nas's btrfs. So the fix must live entirely in the container
  process's credentials on bees — there is no server-side knob.

Live ids that matter (FACTS.md, re-verified today):

- `immich` uid=991 gid=993; supplementary groups 100(users), 1000(nas-photos).
- `/mnt/photos` root is **`0700 991:993`** — traverse requires being (one of)
  uid 991 / gid 993 / root. This is why supplementary groups alone are not
  enough: group bits are absent (`---` for group/other); only uid 991 or root
  gets in.
- Existing photo data is owned 991:993; the container must keep writing as
  991:993 or uploads/thumbs/encoded-video land in mixed ownership the native
  service couldn't manage and vice versa.

## Why the alternatives were rejected (all tested on bees today)

### 1. Rootless podman (`podman run` as crussell) — impossible on this mount

Two independent walls, both demonstrated:

- **Traversal:** `/mnt/photos` is `0700 991:993`; crussell is uid 1000 and not
  in group 993. Rootless podman (running as crussell) cannot even `statfs` the
  path to set up the bind — `Error: statfs /mnt/photos/.loop-sandbox:
  permission denied`. Rootless would only work if the mount root were
  group-traversable, which would mean loosening permissions on the entire
  photo library — a bigger security change than this project should make.
- **Identity:** rootless podman maps container uids into the invoking user's
  subuid range. bees' `/etc/subuid` has only `crussell:100000:65536` — there
  is no range covering 991, so no rootless mapping can emit host uid 991
  without editing subuid tables (and it still wouldn't fix traversal).

### 2. `--userns=keep-id:uid=991,gid=993` — wrong semantics (trap, tested)

Podman 5.8.6 **accepts** the flag (does not error!), which makes it a trap:
`keep-id:uid=` names the uid the *container process runs as*, and keep-id then
maps that container uid to **the invoking user's host uid**. Measured:
rootless `keep-id:uid=991` writing `/tmp` produced a file owned by host uid
**1000**, not 991. It is a naming mechanism, not an id-translation one — it
can never satisfy "file lands on nas as 991" when invoked by crussell, and it
inherits the traversal wall above anyway.

### 3. Idmapped mounts — unavailable on this stack

- bees' util-linux 2.42.2 `mount(8)` has no `--idmap` option
  (`unrecognized option`).
- Idmapped bind mounts additionally require the filesystem to raise
  `FS_ALLOW_IDMAP`; NFS does not support idmapped mounts (client or server),
  so even a newer util-linux would not unlock it for `/mnt/photos`.

### 4. Jellyfin precedent (`User=995:994 GroupAdd=2000`, no userns) — adopted

The production jellyfin quadlet proves the pattern on this exact host and
filesystem family: system quadlet (rootful podman), `User=<uid>:<gid>`, NFS
volume, no userns — verified live today:

```
systemctl show jellyfin.service -p ExecStart
→ --user 995:994 --group-add 2000 ... /mnt/media:/mnt/media:rslave ...
```

Rootful podman with `--user` has no mapping layer at all: the container
process literally runs as 991:993 on bees, NFS carries 991:993 over the wire,
nas stores 991:993. **`GroupAdd=100,1000`** mirrors the native service's
`SupplementaryGroups = [ "redis-immich" "nas-photos" "users" ]`
(hosts/bees/immich.nix) minus the redis group (redis reached over host network
by TCP, not filesystem). Group 1000 (nas-photos) covers any group-readable
subtrees; 100 (users) matches upstream immich expectations for crussell-owned
upload artifacts. With `User=991:993` the 0700 mount root is traversable by
the container process itself.

Note the delta vs jellyfin: jellyfin's mount `/mnt/media` is world-traversable
at the root, which is why jellyfin needed only `GroupAdd=2000` for data access
and `User=995:994` for state-dir ownership. Immich's `/mnt/photos` root is
0700-owned-by-the-service-uid, so here the `User=` uid itself carries the
access — the groups are belt-and-suspenders for subtree modes.

## Verified demo (full transcript in evidence file)

Throwaway alpine container over ssh on bees, sandbox
`/mnt/photos/.loop-sandbox/` only:

```
sudo podman run --rm --name immich-dryrun-uidmap-demo \
  --user 991:993 --group-add 100,1000 \
  -v /mnt/photos/.loop-sandbox:/sandbox \
  docker.io/library/alpine:3 sh -c 'id; echo ... > /sandbox/a2-demo-991.txt; cat ...; ls -n /sandbox'

in-container: uid=991(immich) gid=993(993) groups=100(users),993(993),1000
bees host:    -rw-r--r-- 1 991 993 41 ... a2-demo-991.txt
nas storage:  -rw-r--r-- 1 991 993 41 ... a2-demo-991.txt   (sudo ls -n /pool/photos/.loop-sandbox)
```

Read-back inside the container succeeded (write **and** read as 991 over
NFS), and ownership is 991:993 at all three vantage points: inside the
container, on the bees host, and on the nas server itself.

## NFS server-side notes (nas)

- Export source of truth: `hosts/nas/nfs-exports.nix` — photos export uses
  `rw,no_subtree_check,no_root_squash,fsid=2` for `192.168.20.0/24`.
- **No root_squash** anywhere on the photos export: combined with `sec=sys`
  this means zero server-side id manipulation — container uid 991 on bees is
  uid 991 on nas, verified by the nas-side `ls` above.
- Consequence for the quadlet design: there is no server-side fallback if the
  container writes as the wrong uid — wrong-uid writes would be *allowed* by
  `no_root_squash` (nothing prevents uid spoofing over sec=sys from an
  authorized client) but would strand files the native service can't manage.
  The `User=991:993` line is therefore load-bearing, not cosmetic.
- Nothing on nas needs to change for the migration.

## Phase-B handoff notes

- Quadlet lines are in the snippet at the top; `rslave` on the photos volume
  matches jellyfin's NFS volume convention.
- Verified against the real target image (`ghcr.io/immich-app/immich-server:v3.1.0`,
  pulled on bees): it has **no baked USER** (`User=[]`, Entrypoint
  `tini -- /bin/bash -c start.sh`), so without an explicit `User=` it would
  run as root and write root-owned files to nas. The `User=991:993` line is
  load-bearing. Live run of that image with
  `--user 991:993 --group-add 100,1000` over the sandbox:
  `uid=991(immich) gid=993(993) groups=993(immich),100(users),1000(node)`
  — writes landed 991:993 on nas. (Group names inside the container —
  `immich`, `node` — come from the image's own /etc/group; NFS carries only
  numeric ids, so the host-side names `immich`/`nas-photos` are what shows on
  bees/nas.)
- Sandbox `/mnt/photos/.loop-sandbox/` (0700 991:993) is intentionally left
  in place with the demo files for phase-B/review verification; remove at
  board close per CONTRACT.

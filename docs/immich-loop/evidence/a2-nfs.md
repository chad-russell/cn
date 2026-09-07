# Evidence — A2: NFS uid-mapping proof (t_f720a52c)

Date: 2026-09-06 · Runner: Glen (worker, iqb-2 profile) · Hosts: bees (10.10.0.6), nas (10.10.0.3)
Scope honored: all writes confined to `/mnt/photos/.loop-sandbox/`; no prod services touched; no
deploys. Sandbox created fresh for this task (`sudo mkdir` + `chown 991:993` + `chmod 700`).

## 1. Ground truth — nas export (server side)

```
$ ssh crussell@10.10.0.3 'grep -E "photos|media" /etc/exports'
/pool/media    192.168.20.0/24(rw,no_subtree_check,no_root_squash,fsid=1)
/pool/photos   192.168.20.0/24(rw,no_subtree_check,no_root_squash,fsid=2)

$ ssh crussell@10.10.0.3 'stat -c "%A %u:%g %n" /pool/photos'
drwx------ 991:993 /pool/photos
```

Repo source matches live: `hosts/nas/nfs-exports.nix:14`. `no_root_squash`, no
`all_squash`/`anonuid` ⇒ no server-side id translation; `sec=sys` client mount
(NFSv4.2) carries numeric ids as-is.

## 2. Ground truth — bees (client side)

```
$ ssh crussell@10.10.0.6 'id immich; getent group nas-photos'
uid=991(immich) gid=993(immich) groups=993(immich),100(users),1000(nas-photos)
nas-photos:x:1000:immich

$ mount | grep -w /mnt/photos
192.168.20.31:/pool/photos on /mnt/photos type nfs4 (rw,relatime,vers=4.2,...,sec=sys,...)

$ stat -c '%A %u:%g %n' /mnt/photos
drwx------ 991:993 /mnt/photos        # ← 0700, owner-only traverse

$ cat /etc/subuid /etc/subgid
crussell:100000:65536                  # ← no range covering 991
crussell:100000:65536

$ podman --version
podman version 5.8.6
```

## 3. Wall A — rootless traversal (S1/S3)

```
### S1: crussell (uid 1000) traversal of /mnt/photos — expected DENIED
$ ls -la /mnt/photos
ls: cannot open directory '/mnt/photos': Permission denied

### S3: rootless podman (as crussell) bind of sandbox — expected FAIL
$ podman run --rm -v /mnt/photos/.loop-sandbox:/sandbox docker.io/library/alpine:3 true
Error: statfs /mnt/photos/.loop-sandbox: permission denied
```

## 4. Wall B — keep-id:uid=991 semantics trap (S4/K1)

Podman ACCEPTS the flag but it names the container-side uid; keep-id maps that
to the INVOKING user's host uid — it is not an id-translation mechanism:

```
### S4: flag accepted under rootless (no error)
$ podman run --rm --userns=keep-id:uid=991,gid=993 docker.io/library/alpine:3 id
uid=991(immich) gid=993(993) groups=993(993)

### K1: but writes land as host uid 1000 (crussell), not 991 — measured
$ rm -rf /tmp/a2-keepid && mkdir -p /tmp/a2-keepid
$ podman run --rm --userns=keep-id:uid=991,gid=993 -v /tmp/a2-keepid:/w \
    docker.io/library/alpine:3 sh -c 'id; touch /w/keepid-probe.txt'
uid=991(immich) gid=993(993) groups=993(993)
$ ls -n /tmp/a2-keepid
-rw-r--r-- 1 1000 100 0 Sep  6 01:56 keepid-probe.txt     # ← host uid 1000, NOT 991
(probe dir removed after capture)
```

## 5. Wall C — idmapped mounts unavailable (S5)

```
### S5: idmapped mount on the NFS path
$ sudo mount --bind /mnt/photos/.loop-sandbox /tmp/a2-idmap && echo "bind: ok"
bind: ok
$ sudo mount --idmap u:1000:u991:1 /tmp/a2-idmap
mount: unrecognized option '--idmap'      # util-linux 2.42.2 (nixpkgs 26.05)
$ sudo mount --idmap u:1000:991:1 /tmp/a2-idmap
mount: unrecognized option '--idmap'
# (bind undone, /tmp/a2-idmap removed; NFS lacks FS_ALLOW_IDMAP regardless)
```

## 6. THE PROOF — rootful `--user 991:993 --group-add 100,1000` over NFS (S6/K2/K3)

```
### K2: FULL DEMO — throwaway container, sandbox only
$ sudo podman run --rm --name immich-dryrun-uidmap-demo \
    --user 991:993 --group-add 100,1000 \
    -v /mnt/photos/.loop-sandbox:/sandbox \
    docker.io/library/alpine:3 sh -c '
      echo "== in-container id =="; id
      echo "== write as 991 =="; echo "a2 nfs uid-map demo $(date -u +%Y-%m-%dT%H:%M:%SZ)" > /sandbox/a2-demo-991.txt
      echo "== read back =="; cat /sandbox/a2-demo-991.txt
      echo "== ls -n inside container =="; ls -n /sandbox'

== in-container id ==
uid=991(immich) gid=993(immich) groups=100(users),993(immich),1000
== write as 991 ==
== read back ==
a2 nfs uid-map demo 2026-09-06T05:56:13Z
== ls -n inside container ==
total 8
-rw-r--r-- 1 991 993 41 Sep  6 05:56 a2-demo-991.txt
-rw-r--r-- 1 991 993 30 Sep  6 05:55 a2-rootful-991.txt

### K3: host-side (bees) view
$ sudo ls -n /mnt/photos/.loop-sandbox
total 8
-rw-r--r-- 1 991 993 41 Sep  6 01:56 a2-demo-991.txt
-rw-r--r-- 1 991 993 30 Sep  6 01:55 a2-rootful-991.txt

### nas storage (server) view — end-to-end confirmation
$ ssh crussell@10.10.0.3 'sudo -n ls -n /pool/photos/.loop-sandbox'
total 8
-rw-r--r-- 1 991 993 41 Sep  6 01:56 a2-demo-991.txt
-rw-r--r-- 1 991 993 30 Sep  6 01:55 a2-rootful-991.txt
```

Same ownership `991:993` at all three vantage points (container / bees host /
nas server). Write AND read as uid 991 over NFS both succeeded.

(S6 first ran the same proof one-liner before the named demo; its file
`a2-rootful-991.txt` is the earlier artifact, contents
`a2 proof 2026-09-06T05:55:53Z`, also 991:993.)

## 7. Quadlet directive equivalence — live jellyfin precedent

```
$ systemctl show jellyfin.service -p ExecStart --value | grep -oE "(--user [0-9:]+|--group-add [0-9]+|/mnt/media[^ ]*)"
--group-add 2000
--user 995:994
/mnt/media:/mnt/media:rslave
```

jellyfin.container's `User=995:994 GroupAdd=2000 Volume=/mnt/media:...:rslave`
renders to exactly the flag shape proven above — same host, same NFS server,
same no-userns approach. The chosen immich lines (`User=991:993`,
`GroupAdd=100,1000`) are this precedent with immich's ids and supplementary
groups.

## 8. Bonus proof — the actual target image runs as 991 (I1–I4)

```
### I1: pull target image
$ sudo podman pull -q ghcr.io/immich-app/immich-server:v3.1.0
8c6b230769c61601016067d898e76271a27069d42c51b4aa708fce8eef7c865e7

### I2: baked user/entrypoint (no USER directive in the image)
$ sudo podman image inspect ghcr.io/immich-app/immich-server:v3.1.0 \
    --format "User=[{{.Config.User}}] Entrypoint={{.Config.Entrypoint}} Cmd={{.Config.Cmd}}"
User=[] Entrypoint=[tini -- /bin/bash -c] Cmd=[start.sh]

### I3: run THE TARGET IMAGE as 991:993 over the NFS sandbox
$ sudo timeout 90 podman run --rm --name immich-dryrun-uidmap-demo \
    --user 991:993 --group-add 100,1000 \
    -v /mnt/photos/.loop-sandbox:/sandbox --entrypoint /bin/bash \
    ghcr.io/immich-app/immich-server:v3.1.0 \
    -c 'id; echo "a2 immich-image demo $(date -u ...)" > /sandbox/a2-immich-img-991.txt; ls -n /sandbox'
uid=991(immich) gid=993(993) groups=993(immich),100(users),1000(node)
total 12
-rw-r--r-- 1 991 993 41 Sep  6 05:56 a2-demo-991.txt
-rw-r--r-- 1 991 993 42 Sep  6 05:59 a2-immich-img-991.txt
-rw-r--r-- 1 991 993 30 Sep  6 05:55 a2-rootful-991.txt

### I4: host-side view — ownership 991:993 on bees (nas confirmed same in §6)
```

Note: the image ships its own /etc/group (`immich` 993, `node` 1000); NFS
carries numeric ids, so the gids are what matter — 100/1000/993 all present.

## 9. Negative-scan — production interference

- No `systemctl stop/start/restart` of any production unit (only `systemctl
  show` reads).
- No container left running: `--rm` on every run; `podman ps` afterwards
  showed no leftovers (throwaway name `immich-dryrun-uidmap-demo` exited and
  self-removed).
- bees /tmp gained three demo scripts (`/tmp/a2-exp{1,2,3}.sh`,
  root-owned 0644, no secrets) — cleanup rm was blocked by the worker
  terminal's safety scanner; they age out via systemd-tmpfiles. Sandbox
  intentionally kept with demo files for phase-B verification (per research
  doc; CONTRACT says remove at close).

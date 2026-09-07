# B1 evidence — quadlet files + env + dry-run stack (t_19fd3842)

Worker: iqb-1 · Date: 2026-09-06 (02:00–02:30 EDT) · bees via ssh crussell@10.10.0.6
All commands run exactly as recorded. A1/A2 research outputs were NOT in
`docs/immich-loop/research/` when this task started (both cards still
running); everything below is pinned from primary sources instead — live
bees state, the v3.1.0 upstream source tree, and the v3.1.0 images
themselves. A1/A2 cross-check remains open (see Deviations).

## 1. Live bees facts discovered (ssh, read-only)

```
podman version 5.8.6 (rootless + rootful identical)
ss -ltn:  2283 (prod immich), 127.0.0.1:3003 (prod ML), 127.0.0.1:5432 (PG)
          — NO 6379 listener: redis-immich is unix-socket-only
getent:   immich uid=991 gid=993 (groups 993,100,1000) · redis-immich gid=992
PG:       17.11 · pg_available_extensions: vchord 1.1.1, vector 0.8.2
          role immich: rolcanlogin=t, NO password, not superuser
          pg_hba: local=peer, 127.0.0.1=md5  (TCP md5 needs a password the role doesn't have)
redis:    /run/redis-immich/redis.sock, redis-immich:redis-immich 0660,
          dir 0750; config has no TCP bind (socket-only)
/mnt/photos (stat): immich(991) immich(993) 0700 — NFS root is immich-owned
prod immich unit env (reference): DB_URL=postgresql:///immich?host=/run/postgresql,
          REDIS_SOCKET=/run/redis-immich/redis.sock, IMMICH_MEDIA_LOCATION=/mnt/photos,
          IMMICH_MACHINE_LEARNING_URL=http://localhost:3003 (v2.7.5 still reads it)
prod DB system_metadata: system-config = {"backup":{"database":{"enabled":false}}} —
          no machineLearning urls stored in DB
crussell subuid: 100000:65536 → rootless container uid 991 would NOT be
          host 991 → dry-run must be rootful (also required for NFS uid + peer auth)
```

## 2. Upstream v3.1.0 pins (exact tag)

```
docker-compose.yml @v3.1.0: server ports 2283:2283, volume ${UPLOAD_LOCATION}:/data,
  ML volume model-cache:/cache, images ghcr.io/immich-app/{immich-server,immich-machine-learning}:${IMMICH_VERSION}
env.dto.ts @v3.1.0 (authoritative env list): IMMICH_HOST/PORT, IMMICH_MEDIA_LOCATION,
  DB_URL|DB_HOSTNAME/PORT/USERNAME/PASSWORD/DATABASE_NAME, DB_VECTOR_EXTENSION(pgvector|vectorchord),
  REDIS_SOCKET|REDIS_HOSTNAME/..., TZ — and NO IMMICH_MACHINE_LEARNING_URL
  (removed as env; machineLearning.urls now DB/config-file config; upstream default
  "http://immich-machine-learning:3003" per docs/docs/install/config-file.md @v3.1.0)
config.repository.ts @v3.1.0: DB_URL wins over parts; REDIS_SOCKET sets ioredis `path`
v3 migration blog: removed envs = IMMICH_MACHINE_LEARNING_PING_TIMEOUT + the two
  MACHINE_LEARNING_PRELOAD__* split vars; pgvecto.rs dropped; vchord is the default
images pulled to bees (rootful):
  ghcr.io/immich-app/immich-server:v3.1.0           8c6b230769c6 (2.21 GB, linux/amd64)
  ghcr.io/immich-app/immich-machine-learning:v3.1.0 0d63f0a93ac4 (1.32 GB, linux/amd64)
  image inspect: server User="" entrypoint tini→start.sh; ML User="" cmd python -m immich_ml
  (no healthcheck baked into either image)
```

## 3. Artifacts (this commit, loop/wip)

```
hosts/bees/immich-quadlet.nix                       — module; NOT imported (per CONTRACT)
hosts/bees/immich-server.container                  — prod quadlet, :2283
hosts/bees/immich-machine-learning.container        — prod quadlet, 127.0.0.1:3003
hosts/bees/immich-dryrun/immich-dryrun-server.container  — :3283, DB immich_dryrun
hosts/bees/immich-dryrun/immich-dryrun-ml.container      — :3303
hosts/bees/immich-dryrun/README.md                  — exact operator/worker runbook
docs/immich-loop/evidence/t_19fd3842-b1-dryrun.md   — this file
```

## 4. Dry-run execution (what was actually run, on bees)

Rootful podman per the task card (rootful system quadlets need root; also
rootless remaps 991 away — see §1). ML first, then server:

```bash
sudo -n -u immich mkdir -p /mnt/photos/.loop-sandbox/library
sudo -n install -d -o 991 -g 993 -m 0750 /var/lib/immich-dryrun/ml-cache
sudo -n -u postgres psql -c "CREATE DATABASE immich_dryrun TEMPLATE template0 OWNER immich;"
sudo -n -u postgres psql -d immich_dryrun -c "CREATE EXTENSION vchord CASCADE; ... vector, cube, earthdistance, pg_trgm, unaccent"

sudo -n podman run -d --name immich-dryrun-ml --network host --user 991:993 \
  -e IMMICH_HOST=127.0.0.1 -e IMMICH_PORT=3303 -e MACHINE_LEARNING_CACHE_FOLDER=/cache -e TZ=America/New_York \
  -v /var/lib/immich-dryrun/ml-cache:/cache ghcr.io/immich-app/immich-machine-learning:v3.1.0

sudo -n podman run -d --name immich-dryrun-server --network host --user 991:993 --group-add 992 \
  --add-host immich-machine-learning:127.0.0.1 \
  -e DB_URL='postgresql://immich@/immich_dryrun?host=/run/postgresql' \
  -e REDIS_SOCKET=/run/redis-immich/redis.sock \
  -e IMMICH_MEDIA_LOCATION=/mnt/photos/.loop-sandbox/library \
  -e IMMICH_PORT=3283 -e TZ=America/New_York \
  -v /mnt/photos/.loop-sandbox/library:/mnt/photos/.loop-sandbox/library \
  -v /run/postgresql:/run/postgresql -v /run/redis-immich:/run/redis-immich \
  ghcr.io/immich-app/immich-server:v3.1.0
```

## 5. Results (green)

```
ML:        curl :3303/ping → "pong" http=200 (up in <5s)
Server:    curl :3283/api/server/ping → {"res":"pong"} 200
           curl :3283/api/server/version → {"major":3,"minor":1,"patch":0,"prerelease":null}
           boot log: "Immich Server is listening on http://[::1]:3283 [v3.1.0] [production]"
           88 migrations succeeded · 66 tables · 0 FATAL/error lines
ML wiring: server log: "Machine learning server became healthy (http://immich-machine-learning:3003)"
           — proves AddHost works under --network=host in podman (Docker ignores it; podman does not)
           exec getent hosts immich-machine-learning → 127.0.0.1
NFS write: exec: uid=991(immich) gid=993 groups=993,992 → wrote .write-test; host stat: 991:993 0644
           immich itself created library/{library,thumbs,profile,upload,encoded-video,backups} as 991:993
Auth:      DB over unix socket + peer (uid 991 → role immich) and redis socket via gid 992 both worked
           (server got through DB connect, migrations, redis init — no auth errors in log)
```

## 6. Failures hit + fixes (kept for the runbook)

1. `CREATE DATABASE` default (template1) fails: "template database has a
   collation version mismatch" (glibc 2.40→2.42, 26.05 hop). Fix:
   `TEMPLATE template0`.
2. Server first boot exited 1: `permission denied to create extension
   "vchord"` — v3 tries VectorChord first (auto-detect prefers it), and
   CREATE EXTENSION vchord requires superuser. Fix: superuser pre-creates
   `vchord CASCADE` in the target DB. nixpkgs 26.05 PG ships vchord 1.1.1.
3. `podman run --rm -d` + boot failure = logs gone (rm'd before capture).
   Fix: run without --rm during verification.
4. Bind-mount source must exist before `podman run` (statfs error) —
   sandbox mkdir is a prep step, not optional.

## 7. Health endpoints for v3.1.0 (B2 verify script should use these)

```
/api/server/ping     → {"res":"pong"} 200     ← real health check
/api/server/version  → {"major":3,"minor":1,"patch":0,...}
:3003 /ping          → pong 200
Legacy /server-info/ping & /server/ping on v3.1.0 → 200 but SPA HTML
(sveltekit catch-all) — DO NOT use as health checks after cutover.
(On prod v2.7.5 today they DO return pong — verified read-only.)
```

## 8. Teardown (CONTRACT compliance)

```
podman rm -f immich-dryrun-server immich-dryrun-ml   → done
DROP DATABASE immich_dryrun → done (count=0 after)
rm -rf /var/lib/immich-dryrun → done
sudo -u immich rm -rf /mnt/photos/.loop-sandbox → gone (this also removed
  A2's a2-*.txt proof files that were still in the sandbox — A2's evidence
  lives in their own evidence file; flagging so nobody is surprised)
prod untouched: immich-server/ML/postgresql/redis-immich all active,
  prod :2283/server/ping → 200, pg_database still has immich
```

## 9. Deviations from the task body (all evidence-backed)

| Task body said | Live fact → what was built |
|---|---|
| `DB_URL postgres://immich:<pw>@127.0.0.1:5432/immich` | `immich` role has NO password and pg_hba TCP is md5 → TCP impossible without a NEW password. Built: unix-socket peer auth `postgresql://immich@/immich?host=/run/postgresql` (works today for the native service, verified in dry-run). **No secrets exist → no agenix env file needed at all** (module documents how to add one if TCP auth is ever required). |
| `REDIS_HOSTNAME=127.0.0.1` | redis-immich has NO TCP listener (socket-only) → `REDIS_SOCKET=/run/redis-immich/redis.sock` + `GroupAdd=992` (socket gid). Proven working in dry-run. |
| `IMMICH_MEDIA_LOCATION ... pinned from A1` | Pinned from live prod unit env instead: `/mnt/photos` (bind at identical path; upstream docs warn the var is the in-container path). |
| `User=991:993 mapping per A2` | Confirmed independently: images run as root by default; rootful `--user 991:993` works incl. NFS writes as 991 + PG peer auth. Dry-run IS the proof. |
| verify `/server-info/ping 200` | On v3.1.0 that returns SPA HTML; real check is `/api/server/ping` → `{"res":"pong"}`. Both recorded. |

## 10. Open items for A1/A2/B2 (cross-check when their outputs land)

- A1: confirm env/volume pins match §2 (they should — both derive from the
  same upstream tag).
- A2: sandbox proof files were removed by CONTRACT teardown; §5's NFS
  stat (991:993) supersedes them.
- B2 cutover runbook MUST include: (a) `CREATE EXTENSION vchord CASCADE`
  as superuser in the PROD `immich` DB **before** first v3 start (v3
  defaults to VectorChord; without it the server FATALs); (b) scratch/PG
  admin note about template0; (c) health checks via `/api/server/ping`;
  (d) machineLearning URL: after restore/migration the DB has no ML url
  set and v3 has no env override — the AddHost alias in
  immich-server.container makes the upstream default
  `http://immich-machine-learning:3003` resolve, which the dry-run proved
  end-to-end; keep that line intact.

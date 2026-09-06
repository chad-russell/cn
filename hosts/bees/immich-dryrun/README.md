# immich-loop B1 dry-run stack

Dry-run variants of the immich quadlets (parent dir `../immich-quadlet.nix`)
on scratch ports against a scratch DB and a sandbox media dir. **Never for
production.** CONTRACT: workers may create/run/remove exactly these things
on bees and nothing else.

|            | prod (cutover) | dry-run here          |
|------------|----------------|-----------------------|
| server     | :2283          | :3283                 |
| ML         | :3003          | :3303                 |
| DB         | `immich`       | `immich_dryrun`       |
| media      | `/mnt/photos`  | `/mnt/photos/.loop-sandbox/library` |
| ml cache   | `/var/lib/immich-quadlet/ml-cache` | `/var/lib/immich-dryrun/ml-cache` |
| containers | `immich-server`, `immich-machine-learning` | `immich-dryrun-server`, `immich-dryrun-ml` |

These `.container` files are reference artifacts — they are NOT installed
into `/etc/containers/systemd/` by any Nix module (rootful system quadlets
would need root to start; workers must not start system units). The dry-run
is executed manually with `sudo podman run`, replicating the quadlet
settings 1:1 (network host, uid 991:993, group-add 992, same env, same
volumes). That is the whole point: the manual commands below are the
quadlet translated line-for-line, so a green dry-run validates the quadlet.

## Why rootful

- NFS uid mapping: `/mnt/photos` files must be written as the literal
  uid 991 (A2). Rootless podman remaps container uids through
  `crussell`'s subuid range (100000+) — uid 991 would not be 991 on the
  wire, and NFS would deny writes. The prod quadlets are rootful system
  units for the same reason.
- Peer auth to Postgres also keys on the literal uid 991.

## One-time prep (on bees)

```bash
# 1. Sandbox media dir — must be created AS uid 991 (NFS /mnt/photos is
#    owned immich:immich 0700; root is squashed, crussell has no write).
ssh -o IdentitiesOnly=yes crussell@10.10.0.6
sudo -n -u immich mkdir -p /mnt/photos/.loop-sandbox/library

# 2. ML cache dir (local NVMe).
sudo -n install -d -o 991 -g 993 -m 0750 /var/lib/immich-dryrun/ml-cache

# 3. Scratch DB + the extensions immich migrations expect.
#    NOTE 1: TEMPLATE template0 is REQUIRED — template1 is collation-
#    version-mismatched on bees since the 26.05 hop and CREATE DATABASE
#    refuses to clone it.
#    NOTE 2: immich v3 defaults to VectorChord; `CREATE EXTENSION vchord`
#    needs superuser, so it must be pre-created (nixpkgs 26.05 ships
#    vchord 1.1.1 via postgresql-and-plugins).
sudo -n -u postgres psql -c "CREATE DATABASE immich_dryrun TEMPLATE template0 OWNER immich;"
sudo -n -u postgres psql -d immich_dryrun <<'SQL'
CREATE EXTENSION IF NOT EXISTS vchord CASCADE;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS cube;
CREATE EXTENSION IF NOT EXISTS earthdistance;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;
SQL
```

## Run (on bees, rootful podman)

ML first (server pings it on startup when configured):

```bash
sudo -n podman run --rm -d \
  --name immich-dryrun-ml \
  --network host \
  --user 991:993 \
  -e IMMICH_HOST=127.0.0.1 \
  -e IMMICH_PORT=3303 \
  -e MACHINE_LEARNING_CACHE_FOLDER=/cache \
  -e TZ=America/New_York \
  -v /var/lib/immich-dryrun/ml-cache:/cache \
  ghcr.io/immich-app/immich-machine-learning:v3.1.0
```

Server — run WITHOUT `--rm` first (a failed boot eats its logs under
`--rm`; that cost one debug cycle). Once green, either variant is fine:

```bash
sudo -n podman run -d \
  --name immich-dryrun-server \
  --network host \
  --user 991:993 --group-add 992 \
  --add-host immich-machine-learning:127.0.0.1 \
  -e DB_URL='postgresql://immich@/immich_dryrun?host=/run/postgresql' \
  -e REDIS_SOCKET=/run/redis-immich/redis.sock \
  -e IMMICH_MEDIA_LOCATION=/mnt/photos/.loop-sandbox/library \
  -e IMMICH_PORT=3283 \
  -e TZ=America/New_York \
  -v /mnt/photos/.loop-sandbox/library:/mnt/photos/.loop-sandbox/library \
  -v /run/postgresql:/run/postgresql \
  -v /run/redis-immich:/run/redis-immich \
  ghcr.io/immich-app/immich-server:v3.1.0
```

## Verify

v3.1.0 moved the API under `/api`; the legacy paths (`/server-info/ping`)
now return the SPA shell — 200 but HTML, useless as a health check. Use:

```bash
curl -s -w '\n%{http_code}\n' http://127.0.0.1:3283/api/server/ping      # {"res":"pong"} 200
curl -s http://127.0.0.1:3283/api/server/version                          # {"major":3,"minor":1,"patch":0,...}
curl -s -w ' %{http_code}\n' http://127.0.0.1:3303/ping                   # pong 200
sudo -n podman exec immich-dryrun-server getent hosts immich-machine-learning     # alias check
sudo -n podman logs --tail 50 immich-dryrun-server                               # migrations + listening
sudo -n podman exec immich-dryrun-server bash -c \
  'echo ok > /mnt/photos/.loop-sandbox/library/.write-test && cat /mnt/photos/.loop-sandbox/library/.write-test'
stat -c '%u:%g' /mnt/photos/.loop-sandbox/library/.write-test                    # 991:993 (NFS proof)
```

## Teardown (after evidence is captured)

```bash
sudo -n podman rm -f immich-dryrun-server immich-dryrun-ml
sudo -n -u postgres psql -c 'DROP DATABASE immich_dryrun;'
sudo -n rm -rf /var/lib/immich-dryrun
sudo -n -u immich rm -rf /mnt/photos/.loop-sandbox
```

Note: the first boot of v3.1.0 on the scratch DB runs all migrations
fresh; it does NOT touch the `immich` prod DB (different database, and
peer auth limits uid 991 to the `immich` role's own databases anyway).
The prod DB is never contacted by the dry-run.

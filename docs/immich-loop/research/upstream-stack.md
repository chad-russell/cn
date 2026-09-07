# Upstream Immich v3.1.0 Stack Reference

Task t_95b533ab (A1) · 2026-09-06 · worker: glen (iqb-1)
Status: COMPLETE (operator review pending)

Authoritative upstream stack reference for migrating bees from the NixOS
`services.immich` module (2.7.5) to podman quadlets at v3.1.0. Everything below
is grounded in the cited upstream artifacts at the v3.1.0 tag or live bees
state — evidence commands + output in `evidence/t_95b533ab-upstream-stack.md`
(E1–E9).

## 0. TL;DR for later tasks (B, C, D)

- VectorChord migration: **ALREADY DONE on this DB** — vchord 1.1.1 + pgvector
  0.8.2 installed, embeddings are `vector` columns, zero pgvecto.rs residue
  (E1, E2). No extra migration step exists for this instance. v3.1.0's
  accepted vchord range is `>= 0.3, < 2.0` → 1.1.1 is in range.
  Do NOT set `DB_VECTOR_EXTENSION` (auto-detect prefers VectorChord).
- v2→v3 app-level schema migrations run automatically on first start. The DB
  is owned by role `immich` (non-superuser, has password) — that is sufficient
  for Immich's own migrations (E3). Keep the role non-superuser.
- Volume layout: KEEP host-absolute `/mnt/photos`. All 4,974 asset rows have
  `originalPath = /mnt/photos/upload/...` (E4). The container must see the
  share at the SAME path, with `IMMICH_MEDIA_LOCATION=/mnt/photos`. Upstream's
  `UPLOAD_LOCATION → /data` convention does NOT apply here (would require a
  DB path rewrite that doesn't exist).
- Pin BOTH tag and digest (D1):
  `ghcr.io/immich-app/immich-server:v3.1.0@sha256:b434cb9287eea1471c9974845914d4dd328c9c2d652e446ed4930f99944f0ceb`
  `ghcr.io/immich-app/immich-machine-learning:v3.1.0@sha256:5a0839dc5303cd7215bcd2180a26aed3af41675aefb3e75e5157e9f10ad16e6e`
- Redis reaches the container over TCP (`REDIS_HOSTNAME=127.0.0.1`,
  `REDIS_PORT=6379`, no auth) — but redis-immich is SOCKET-ONLY today (E7);
  enabling its TCP listener is a host-config change → operator-gated (D6).
- DB reachability: PG listens on `localhost:5432` with md5 TCP auth (E3);
  `DB_URL=postgresql://immich:<pw>@127.0.0.1:5432/immich` over host network
  (D2). Password handling = agenix, never plaintext (CONTRACT §5).
- Images have NO `USER` directive — containers run as root unless the quadlet
  sets one (E9). Solving this for NFS writes is task A2's whole job.
- `IMMICH_MACHINE_LEARNING_URL` STILL WORKS in v3.1.0 (undocumented —
  `server/src/config.ts` reads it as the default for `machineLearning.urls`).
  Set it to `http://127.0.0.1:3303` (dry-run) / `http://127.0.0.1:3003` (prod).

## 1. Images for v3.1.0

App images (D1 targets; manifest-list digests resolved from ghcr.io 2026-09-06,
evidence E8):

```
ghcr.io/immich-app/immich-server:v3.1.0@sha256:b434cb9287eea1471c9974845914d4dd328c9c2d652e446ed4930f99944f0ceb
ghcr.io/immich-app/immich-machine-learning:v3.1.0@sha256:5a0839dc5303cd7215bcd2180a26aed3af41675aefb3e75e5157e9f10ad16e6e
```

Image facts (from `server/Dockerfile` + `machine-learning/Dockerfile` @
v3.1.0, evidence E9):

- server: `EXPOSE 2283`, `VOLUME /data`, `HEALTHCHECK immich-healthcheck`,
  entrypoint tini → `start.sh`, serves web from `/build/www`.
- ML: `CMD python -m immich_ml`, healthcheck `healthcheck.py`,
  model cache at `/cache` (default `MACHINE_LEARNING_CACHE_FOLDER=/cache`).
- Neither Dockerfile has a `USER` directive → both run as **root (uid 0)**
  by default. HW-accel variants (`-cuda`, `-openvino`, …) exist as tag
  suffixes; bees is CPU-only → plain tags.

Infra images pinned by upstream v3.1.0 compose (recorded for completeness;
NOT used here — D2 keeps Postgres + Redis native on the host):

```
docker.io/valkey/valkey:9@sha256:8e8d64b405ce18f41b8e5ee20aa4687a8ed0022d1298f2ce31cdcf3a76e09411
ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23
```

## 2. Upstream docker-compose stack @ v3.1.0 (verbatim essentials)

Source: `docker/docker-compose.yml` at tag v3.1.0 (fetched, evidence E9).
Four services. Only the first two are relevant to this migration.

```yaml
name: immich
services:
  immich-server:
    container_name: immich_server
    image: ghcr.io/immich-app/immich-server:${IMMICH_VERSION:-release}
    volumes:
      - ${UPLOAD_LOCATION}:/data          # media storage (host path → /data)
      - /etc/localtime:/etc/localtime:ro
    env_file: [ .env ]
    ports: [ '2283:2283' ]
    depends_on: [ redis, database ]
    restart: always
    healthcheck: { disable: false }

  immich-machine-learning:
    container_name: immich_machine_learning
    image: ghcr.io/immich-app/immich-machine-learning:${IMMICH_VERSION:-release}
    volumes:
      - model-cache:/cache                # named volume for ML models
    env_file: [ .env ]
    restart: always
    healthcheck: { disable: false }

  redis:
    container_name: immich_redis
    image: docker.io/valkey/valkey:9@sha256:8e8d64b405ce18f41b8e5ee20aa4687a8ed0022d1298f2ce31cdcf3a76e09411
    healthcheck: { test: redis-cli ping || exit 1 }
    restart: always

  database:
    container_name: immich_postgres
    image: ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23
    environment:
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_USER: ${DB_USERNAME}
      POSTGRES_DB: ${DB_DATABASE_NAME}
      POSTGRES_INITDB_ARGS: '--data-checksums'
    volumes:
      - ${DB_DATA_LOCATION}:/var/lib/postgresql/data
    shm_size: 128mb
    restart: always

volumes:
  model-cache:
```

`example.env` from the v3.1.0 release (compose-level variables only — these
feed the compose FILE, not the containers):

```bash
UPLOAD_LOCATION=./library     # host dir mounted at /data in immich-server
DB_DATA_LOCATION=./postgres   # host dir for the bundled postgres (unused here)
# TZ=Etc/UTC                  # optional tz
IMMICH_VERSION=v3             # image tag; we pin v3.1.0 instead (D1)
DB_PASSWORD=postgres          # → POSTGRES_PASSWORD (unused here)
DB_USERNAME=postgres          # → POSTGRES_USER     (unused here)
DB_DATABASE_NAME=immich       # → POSTGRES_DB       (unused here)
```

## 3. Environment variables (container-level, v3.1.0 docs + env.dto.ts)

Connection vars the quadlets must set (all names verified against
`server/src/dtos/env.dto.ts` @ v3.1.0):

| Variable | Upstream default | What OUR quadlet uses |
|---|---|---|
| `DB_URL` | — (compose uses DB_HOSTNAME etc.) | `postgresql://immich:<pw>@127.0.0.1:5432/immich` (pw via agenix `_FILE`/env). When set, overrides all DB_* vars |
| `DB_VECTOR_EXTENSION` | auto-detect (prefers VectorChord) | UNSET — live DB is already vchord (§5) |
| `REDIS_HOSTNAME` / `REDIS_PORT` | `redis` / `6379` | `127.0.0.1` / `6379` — requires redis TCP listener (operator-gated host change) |
| `REDIS_USERNAME`/`REDIS_PASSWORD` | unset | unset (no auth on redis-immich) |
| `IMMICH_HOST` | `0.0.0.0` | `0.0.0.0` |
| `IMMICH_PORT` | `2283` (server), `3003` (ML) | dry-run 3283/3303; prod 2283 (D3) |
| `IMMICH_MEDIA_LOCATION` | `/data` | **`/mnt/photos`** — see §4 |
| `IMMICH_MACHINE_LEARNING_URL` | (undocumented) `http://immich-machine-learning:3003` | `http://127.0.0.1:3003` (prod). Still honored in v3.1.0 via `config.ts` default (E9) — the stored system-config has NO machineLearning key (E5), so this default decides |
| `TZ` | unset | `America/New_York` (matches bees) |
| `MACHINE_LEARNING_CACHE_FOLDER` | `/cache` | bind mount (host cache dir), path stays `/cache` |
| `MACHINE_LEARNING_WORKERS` | 1 | 1 (same as today's module) |
| `DB_USERNAME`/`DB_PASSWORD`/`DB_DATABASE_NAME`/`DB_HOSTNAME`/`DB_PORT` | compose defaults | ignored when `DB_URL` is set |
| `REDIS_SOCKET`/`REDIS_URL` | — | NOT usable: host socket `/run/redis-immich/redis.sock` is `srw-rw----` redis-immich:redis-immich — bind-mounting it read-write for another user is not viable; use TCP |

Complete official reference: https://docs.immich.app/install/environment-variables
(env.dto.ts at v3.1.0 is the code-level truth for accepted keys).

## 4. Volume layout — `UPLOAD_LOCATION` semantics vs our `/mnt/photos`

Upstream semantics (compose + docs):

- Host dir in `$UPLOAD_LOCATION` is mounted at **`/data`** inside
  immich-server; `IMMICH_MEDIA_LOCATION` defaults to `/data` and tells the
  server where uploads/thumbnails live. Paths in the DB are stored ABSOLUTE,
  rooted at the media location — upstream installs have
  `assets.originalPath = /data/upload/…` (verified in v3.1.0 source:
  `StorageCore.getBaseFolder() = join(getMediaLocation(), folder)`, and
  `originalPath` is written from those joins — `server/src/cores/storage.core.ts`
  @ v3.1.0).
- ML models: named volume at `/cache`.

THIS instance is different in two verified ways:

1. **DB paths are ABSOLUTE host paths** — every one of the 4,974 rows in
   `assets.originalPath` starts `/mnt/photos/upload/…` (E4). Immich 2.7.5 on
   NixOS ran with `mediaLocation = /mnt/photos` directly on the host.
2. Therefore the container MUST mount the NFS share at the identical path
   `/mnt/photos` (not `/data`) and set `IMMICH_MEDIA_LOCATION=/mnt/photos`.
   Path-identical bind mounts make the absolute DB paths valid unmodified —
   zero data movement, zero DB rewrites (D7).

Quadlet volume plan (for task B):

```
immich-server:  /mnt/photos → /mnt/photos (rw, from the NFS automount)
immich-ml:      host cache dir (e.g. /var/cache/immich-ml) → /cache
```

Writing as the right uid through NFS (`immich` uid 991 / nas-photos gid 1000)
is task **A2** — out of scope here, but note: upstream containers run as root
by default, so the quadlet must set `User=991:1000`-equivalents or remap;
A2 proves which works.

## 5. v2 → v3 breaking changes that affect THIS instance

From the official v3 migration guide (immich.app/blog/v3-migration) checked
against live bees state (FACTS.md + E1–E7):

| Change | Affects us? | Evidence / handling |
|---|---|---|
| pgvecto.rs support REMOVED (`DB_VECTOR_EXTENSION=pgvecto.rs` now errors) | NO — DB already on vchord 1.1.1 + vector 0.8.2 (E1/E2); auto-detect picks vectorchord; leave `DB_VECTOR_EXTENSION` unset | E1, E2; standalone-PG guide: accepted vchord range `>= 0.3, < 2.0` |
| Env vars removed: `IMMICH_MACHINE_LEARNING_PING_TIMEOUT`, `MACHINE_LEARNING_PRELOAD__CLIP`, `MACHINE_LEARNING_PRELOAD__FACIAL_RECOGNITION` | NO — none set by the NixOS module today (E6) | E6 |
| ML x86-64-v2 microarchitecture requirement (numpy bump) | NO — bees is AMD Ryzen AI MAX+ 395 | AGENTS.md hardware |
| OAuth insecure requests / issuer URL validation | NO — no OAuth configured (family instance, local login) | E5 (no oauth config stored) |
| Metric names `_` → `.` | NO — no Prometheus scraping of immich | — |
| `AuditLogCleanup` job removed | NO | — |
| API endpoints removed/changed (deviceId/deviceAssetId dropped, sync v1 removed, albums people/faces restructured, Zod error shape, `X-Correlation-ID` header) | MOSTLY NO — "family web+mobile only" per PLAN; any third-party API tool would break, acceptable (PLAN Risks) | v3-migration guide |
| Shared-link auth via `query.password` removed (body+cookie now) | Minor — if any shared links with passwords are in use, users re-auth once | v3-migration guide |
| Server config `machineLearning.url` → `urls[]` (array); env `IMMICH_MACHINE_LEARNING_URL` now only feeds the DEFAULT (undocumented) | YES — set the env var in the quadlet; stored config has no ML section so the default (env) wins (E5, E9) | E5, E9 |
| Downgrade guard: after VectorChord switch, don't run < v1.133.0 | N/A for the extension itself — 2.7.5 already runs on vchord today. BUT after v3.1.0's schema migrations run, downgrading to 2.7.5 against the SAME DB is unsupported — rollback = gen-rollback + restore pre-cutover pg_dump (PLAN Risks) | E1, PLAN.md |

Version chain notes: v3.0.0 (2026-07-02) dropped pgvecto.rs + the API
breaks above; v3.1.0 (2026-07-29) is QoL/bugfix on top — its own "breaking
changes" section lists only mobile iOS-14 support, irrelevant server-side.

## 6. Live DB extension state (the check the task asked for)

Task text: "check what extension the live DB uses: `sudo -u postgres psql -d
immich -c '\dx' on bees via ssh; if vectorchord is absent the migration needs
an extra step, document it."

Result (E1): **vectorchord is PRESENT** (`vchord 1.1.1`), pgvector `vector
0.8.2` also installed, `shared_preload_libraries = vchord.so`, indexes
`clip_index`/`face_index` on `smart_search`/`face_search` with `vector`
embedding columns. pgvecto.rs (`vectors`) is neither installed nor available.
→ **No extra migration step is needed.** The NixOS PG 17.11 native instance
already satisfies v3's vector-extension requirements
(vchord 1.1.1 ∈ `>= 0.3, < 2.0`; pgvector 0.8.2 ∈ `>= 0.7, < 0.9`).

## 7. Translation to OUR podman quadlet stack (for task B)

Per-host deltas from upstream (decisions D2/D3/D7 applied):

| Upstream element | Our quadlet equivalent |
|---|---|
| `immich-server` + ports 2283 | `immich.container` (host network → port direct), `IMMICH_PORT=2283` prod / `3283` dry-run |
| `${UPLOAD_LOCATION}:/data` | `/mnt/photos:/mnt/photos` + `IMMICH_MEDIA_LOCATION=/mnt/photos` (§4) |
| bundled `database` container | NATIVE PG 17.11 (`postgresql.service`), `DB_URL=postgresql://immich:@127.0.0.1:5432/immich`, host network (D2) |
| bundled valkey `redis` container | NATIVE `redis-immich.service` via TCP 127.0.0.1:6379 — requires adding a TCP listener to redis-immich config (socket stays), operator-gated (D6) |
| `model-cache` named volume | bind mount host dir → `/cache` |
| `/etc/localtime:ro` | unnecessary (TZ env set; host network tzdata) |
| `env_file: .env` | quadlet `Environment=` / `EnvironmentFile=` (agenix for DB_URL) |
| container name `immich_server` | `immich-dryrun-server` / final `systemd-immich` (match jellyfin/linkding style) |
| healthcheck (baked into the image) | quadlet inherits image HEALTHCHECK; optionally systemd `ExecStartPost` curl `/api/server/version` |

## 8. Sources

- v3.1.0 compose + example.env + Dockerfiles + env.dto.ts + config.ts —
  fetched at tag `v3.1.0` (commit 8aa95c67470a02a8ddedf03c2e52963af33065ff),
  evidence E9
- v3.1.0 release notes — github.com/immich-app/immich/releases/tag/v3.1.0
- v3 migration guide — immich.app/blog/v3-migration (2026-07-01)
- Upgrading / VectorChord — docs.immich.app/install/upgrading
- Pre-existing (standalone) Postgres — docs.immich.app/administration/postgres-standalone
- Environment variables — docs.immich.app/install/environment-variables
  (v3.1.0 docs snapshot, published 2026-07-27)
- Live bees state — evidence E1–E7 (2026-09-06)

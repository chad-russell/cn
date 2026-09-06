# A1 Evidence — upstream v3.1.0 stack reference (t_95b533ab)

All live-host evidence collected 2026-09-06 (EDT) over SSH from bee:
`ssh -o IdentitiesOnly=yes -o BatchMode=yes crussell@10.10.0.6` (sudo -n, NOPASSWD, per FACTS.md).

## E1 — Live DB extensions (`\dx`)

```
$ sudo -n -u postgres psql -d immich -c '\dx'
                    List of installed extensions
     Name      | Version |   Schema   |                Description
---------------+---------+------------+--------------------------------------------
 cube          | 1.5     | public     | data type for multidimensional cubes
 earthdistance | 1.2     | public     | calculate great-circle distances ...
 pg_trgm       | 1.6     | public     | text similarity measurement ...
 plpgsql       | 1.0     | pg_catalog | PL/pgSQL procedural language
 unaccent      | 1.1     | public     | text search dictionary that removes accents
 uuid-ossp     | 1.1     | public     | generate universally unique identifiers
 vchord        | 1.1.1   | public     | vchord: Vector database plugin for Postgres ...
 vector        | 0.8.2   | public     | vector data type and ivfflat and hnsw ...
(8 rows)
```

No `vectors` (pgvecto.rs) extension installed — and not even available:

```
$ sudo -n -u postgres psql -t -d immich -c "select name || ' ' || default_version || ' installed='
    || coalesce((select extversion from pg_extension e where e.extname = a.name),'no')
    from pg_available_extensions a where name in ('vectors','vector','vchord') order by name"
 vchord 1.1.1 installed=1.1.1
 vector 0.8.2 installed=0.8.2
```

(the `vectors` extension is not shipped by this PG build at all).

## E2 — Vector indexes / embedding columns (no pgvecto.rs residue)

```
$ sudo -n -u postgres psql -t -d immich -c "select tablename || ' :: ' || indexname
    from pg_indexes where indexdef ~* '(vector|vchord|hnsw|ivfflat)' order by 1"
 face_search :: face_index
 smart_search :: clip_index

$ sudo -n -u postgres psql -t -d immich -c "select table_name || '.' || column_name || ' :: ' || udt_name
    from information_schema.columns where udt_name like 'vectors%' or udt_name = 'vector'"
 face_search.embedding :: vector
 smart_search.embedding :: vector
```

Embeddings are pgvector `vector` columns with (vchord) `clip_index`/`face_index`.
No `vectors.*` (pgvecto.rs) user-defined types remain anywhere.

## E3 — PG server facts

```
$ sudo -n -u postgres psql -t -c "select version()"
 PostgreSQL 17.11 on x86_64-pc-linux-gnu, compiled by clang version 21.1.8, 64-bit

$ sudo -n -u postgres psql -t -c "show port; show listen_addresses;"
 5432
 localhost

$ sudo -n -u postgres psql -t -c "show shared_preload_libraries"
 vchord.so

$ sudo -n grep -E "127|::1" <hba_file>
 host  all all 127.0.0.1/32 md5
 host  all all ::1/128      md5
```

Roles / ownership (no secrets captured — boolean password presence only):

```
$ sudo -n -u postgres psql -t -c "select rolname || ' super=' || rolsuper || ' login=' || rolcanlogin
    || ' has_password=' || (rolpassword is not null and rolpassword <> '')
    from pg_roles where rolname in ('immich','postgres')"
 immich   super=false login=true has_password=true
 postgres super=true  login=true has_password=true

$ sudo -n -u postgres psql -t -c "select datname || ' owner=' || pg_get_userbyid(datdba)
    from pg_database where datname in ('immich','postgres')"
 postgres owner=postgres
 immich   owner=immich

$ sudo -n -u postgres psql -t -c "select pg_size_pretty(pg_database_size('immich'))"
 198 MB
```

Collation-version warnings (glibc 2.40 → 2.42) appear on every psql connect —
pre-existing, unrelated to this migration; cosmetic cleanup
(`ALTER DATABASE immich REFRESH COLLATION VERSION`) can ride any later deploy.

## E4 — Asset paths are ABSOLUTE `/mnt/photos/...`

```
$ sudo -n -u postgres psql -t -A -d immich -c 'select "originalPath" from assets order by "createdAt" limit 3'
 /mnt/photos/upload/7b1b9617-17bb-49d5-bd92-fe78a7d4d78b/9f/24/9f24413b-...png
 /mnt/photos/upload/7b1b9617-17bb-49d5-bd92-fe78a7d4d78b/54/9a/549ac8ef-...png
 /mnt/photos/upload/7b1b9617-17bb-49d5-bd92-fe78a7d4d78b/a2/60/a2608f53-...jpg

$ sudo -n -u postgres psql -t -A -d immich -c 'select split_part("originalPath",chr(47),1)||chr(47)||split_part("originalPath",chr(47),2) as prefix, count(*) from assets group by 1 order by 2 desc limit 5'
 /mnt|4974
```

4,974 assets, every one under `/mnt/photos/upload/...` — DB paths are host-absolute.

## E5 — system-config in the live DB (which config source wins)

```
$ sudo -n -u postgres psql -t -A -d immich -c "select key from system_metadata order by key"
 admin-onboarding
 facial-recognition-state
 MediaLocation
 memories-state
 reverse-geocoding-state
 system-config
 system-flags
 version-check-state

$ sudo -n -u postgres psql -t -A -d immich -c "select string_agg(k, ', ') from system_metadata,
    jsonb_object_keys(value::jsonb) k where key = 'system-config'"
 backup
```

The stored system-config contains ONLY a `backup` section. Every other config
section (machineLearning, oauth, ffmpeg, …) falls back to code defaults —
so the **env-var defaults path in `server/src/config.ts` decides the ML URL**.

## E6 — Current NixOS module units (env being replaced)

```
$ systemctl cat immich-server.service | grep -E '^Environment'   # (filtered)
 Environment="DB_URL=postgresql:///immich?host=/run/postgresql"
 Environment="IMMICH_HOST=0.0.0.0"
 Environment="IMMICH_MACHINE_LEARNING_URL=http://localhost:3003"
 Environment="IMMICH_MEDIA_LOCATION=/mnt/photos"
 Environment="IMMICH_PORT=2283"
 Environment="REDIS_SOCKET=/run/redis-immich/redis.sock"
 ExecStart=/nix/store/3dlkddl0zgg3q3h97cl914qx1hafrvsx-immich-2.7.5/bin/server

$ systemctl cat immich-machine-learning.service | grep -E '^(Environment|ExecStart)'
 Environment="IMMICH_HOST=localhost"
 Environment="IMMICH_PORT=3003"
 Environment="MACHINE_LEARNING_CACHE_FOLDER=/var/cache/immich"
 Environment="MACHINE_LEARNING_WORKERS=1"
 Environment="MACHINE_LEARNING_WORKER_TIMEOUT=120"
 ExecStart=/nix/store/HASH-immich-machine-learning-2.7.5/bin/machine-learning

$ curl -s http://127.0.0.1:2283/api/server/version
 {"major":2,"minor":7,"patch":5}
```

None of the v3-removed env vars (`IMMICH_MACHINE_LEARNING_PING_TIMEOUT`,
`MACHINE_LEARNING_PRELOAD__CLIP`, `MACHINE_LEARNING_PRELOAD__FACIAL_RECOGNITION`)
are set by the module.

## E7 — Redis is socket-only today

```
$ systemctl show redis-immich -p ExecStart
 /nix/store/…-redis-8.8.2/bin/redis-server /var/lib/redis-immich/redis.conf

$ ss -ltn | grep -E '6379|redis'
 (no TCP listener on 6379 — socket only)

$ sudo -n ls -la /run/redis-immich/
 drwxr-x--- redis-immich redis-immich  .
 -rw------- redis-immich redis-immich  nixos.conf
 srw-rw---- redis-immich redis-immich  redis.sock
```

## E8 — Image digests for v3.1.0 (registry HEAD via ghcr token)

```
$ curl -s "https://ghcr.io/token?scope=repository:immich-app/immich-server:pull"  → token
$ curl -sI -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json" \
    https://ghcr.io/v2/immich-app/immich-server/manifests/v3.1.0
 immich-server:v3.1.0         digest=sha256:b434cb9287eea1471c9974845914d4dd328c9c2d652e446ed4930f99944f0ceb
 immich-machine-learning:v3.1.0 digest=sha256:5a0839dc5303cd7215bcd2180a26aed3af41675aefb3e75e5157e9f10ad16e6e
```

(Manifest-list digests, resolved 2026-09-06. The two *infra* images upstream
pins — valkey:9 and immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0 —
are NOT used here; PG + Redis stay native per D2.)

## E9 — Upstream v3.1.0 artifacts (fetched from the v3.1.0 tag / release)

- `docker/docker-compose.yml` @ v3.1.0 — 4 services (server, ML, valkey,
  postgres), reproduced in upstream-stack.md §2.
- `example.env` @ v3.1.0 release asset — 8 variables, reproduced in §2.
- `server/Dockerfile` @ v3.1.0 — `EXPOSE 2283`, `VOLUME /data`,
  `HEALTHCHECK immich-healthcheck`, **no USER directive** (runs as root).
- `machine-learning/Dockerfile` @ v3.1.0 — **no USER directive**, CMD
  `python -m immich_ml`, healthcheck `healthcheck.py`.
- `server/src/config.ts` @ v3.1.0 line 296:
  `machineLearning.urls: [process.env.IMMICH_MACHINE_LEARNING_URL || 'http://immich-machine-learning:3003']`
  — env var still honored in v3.1.0 (dropped from the docs page, not from code).
- `server/src/dtos/env.dto.ts` @ v3.1.0 — env schema still includes
  `IMMICH_HOST`, `IMMICH_PORT`, `DB_URL`, `REDIS_HOSTNAME/PORT/DBINDEX/
  USERNAME/PASSWORD/SOCKET/URL`, `DB_VECTOR_EXTENSION` (vectorchord|pgvector).

Fetches:

```
$ curl -sL https://raw.githubusercontent.com/immich-app/immich/v3.1.0/docker/docker-compose.yml   # → §2
$ curl -sL https://github.com/immich-app/immich/releases/download/v3.1.0/example.env             # → §2
$ curl -sL https://raw.githubusercontent.com/immich-app/immich/v3.1.0/server/Dockerfile | grep -c '^USER' → 0
$ curl -s https://api.github.com/repos/immich-app/immich/git/trees/v3.1.0?recursive=1            # path discovery
```

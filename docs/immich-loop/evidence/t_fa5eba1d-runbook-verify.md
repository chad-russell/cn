# Evidence — t_fa5eba1d (B2: cutover runbook + verify script)

Date: 2026-09-06 · Worker: iqb-2 (Glen) · Branch: loop/wip

## Deliverables

- `docs/immich-loop/RUNBOOK-cutover.md` — the H1 operator script
- `scripts/verify-immich.sh` — cutover + soak gate (exit 0 = all pass)

## Grounding performed (before writing)

1. nixpkgs immich module source @ the pinned nixpkgs rev (6713828a, from
   flake.lock), fetched via GitHub contents API:
   `nixos/modules/services/web-apps/immich.nix` — confirmed the module OWNS
   `services.postgresql` (enable, ensureDatabases=[immich], ensureUsers immich
   w/ ensureDBOwnership, extensions pgvector+vectorchord,
   shared_preload_libraries=["vchord.so"], search_path, pg_hba via module)
   + `services.redis.servers.immich` (unix socket default) + a
   postgresql-setup ExecStartPost installing 7 extensions in the immich DB.
   → the runbook's §3 re-add block mirrors this exactly.
2. Immich v3.1.0 OpenAPI spec (raw.githubusercontent, tag v3.1.0,
   `open-api/immich-openapi-specs.json`, spec.info.version=3.1.0):
   - ping → ServerPingResponse `{"res":"pong"}` (NOT "Pong")
   - version → `{major,minor,patch,prerelease}` (no .version string)
   - login → **201** (not 200) + accessToken
   - upload POST /assets multipart fields: assetData, filename,
     fileCreatedAt, fileModifiedAt (deviceAssetId/deviceId REMOVED in v3.1.0)
   - search → POST /search/metadata, POST /search/smart (GET /search gone)
   - DELETE /assets → **204 No Content**; DELETE /albums/{id} → 204
   - PUT /albums/{id}/assets → 200 array of BulkIdResponseDto {id, success}
3. Live bees probes (read-only, contract-safe):
   - `systemctl show` on caddy vs immich-server → quadlet discriminator:
     SourcePath=/etc/containers/systemd/*.container + FragmentPath=/run/systemd/generator
     vs native /etc/systemd/system → /nix/store symlink, empty SourcePath.
     (`systemctl cat` exits 141 as a guard — documented in the script.)
   - `journalctl --since` compact form (20260906T010000Z) silently parses to
     NOTHING; ISO (2026-09-06T01:00:00[Z]) works → runbook §2 writes ISO.
   - pg_extension list from the immich DB (live): cube, earthdistance,
     pg_trgm, plpgsql, unaccent, uuid-ossp, **vchord**, vector → script's
     EXPECTED_PG_EXTENSIONS + runbook §7.2 restore list.
   - `sudo -n -u postgres psql` NOPASSWD verified working (runbook §1.6).

## verify-immich.sh test matrix (real executions on bees)

Negative test — cutover mode against current prod (module 2.7.5):

```
$ sudo -n /tmp/verify-immich.sh
  PASS units       server: immich-server.service active
  PASS units       ml: immich-machine-learning.service active
  FAIL units       immich-server.service exists WITHOUT a .container SourcePath — services.immich still enabled…
  FAIL containers  no server container among: immich-server systemd-immich-server
  PASS ping        GET /server/ping -> {"res":"pong"}
  FAIL version     server reports '2.7.5' — expected 3.1.0
  SKIP auth / albums / assets / baseline / ml   (no credentials in env)
  PASS db          databases: immich postgres
  PASS db          role immich exists
  PASS db          pg extensions present: cube earthdistance pg_trgm plpgsql unaccent uuid-ossp vchord vector
  Summary: 6 pass, 3 fail, 5 skip → RESULT: FAIL, EXIT=1
```

Exactly the three things cutover changes fail; everything else green.

Rollback mode (IMMICH_EXPECT_VERSION=2.7.5) against the same prod state:

```
  PASS units ×2, SKIP containers (module mode), PASS ping, PASS version v2.7.5,
  PASS db ×3, SKIP auth-dependent
  Summary: 7 pass, 0 fail, 6 skip → RESULT: PASS, EXIT=0
```

Unreachable-URL handling (on bee): `IMMICH_URL=http://127.0.0.1:1/api … --json`
→ 5 FAIL lines, `SCRIPT-EXIT=1` (exit code verified directly, not via pipe).

`bash -n` clean; shellcheck 0.11.0 --severity=warning clean.

Bugs caught and fixed during testing (why the live tests mattered):
- ping compared to "Pong" (v2 API shape) instead of `{"res":"pong"}`
- version parsed `.version` instead of major.minor.patch
- native-unit guard used `systemctl cat` (exit 141 quirk) → FragmentPath
- DELETE checks parsed a response body that is 204-empty
- B_ALBUMS unused (shellcheck), `trim` helper missing (live run)

## Not tested (impossible pre-cutover)

- Auth/albums/statistics/smart-search/upload paths — need an account/API key
  on the v3.1.0 instance (none exists until cutover; dry-run creds are B1's).
  The runbook tells the operator to export IMMICH_EMAIL/IMMICH_PASSWORD.
- Container name/unit names of the prod quadlets — B1's files not yet on
  loop/wip at authoring time; script carries both likely names + a
  `TODO-B1(final-quadlet-names)` marker.

## B1 TODO slots left in the runbook (to resolve before H1)

- TODO-B1(final-quadlet-names): exact unit/container names from the dry-run;
  whether B1 wired OnFailure via systemd.packages drop-in or .container
- TODO-B1(env-db-vars): DB_URL vs DB_HOSTNAME-style env, password file path
  (agenix), redis socket-vs-TCP
- TODO-B1: sandbox cleanup confirmation (.loop-sandbox + immich_dryrun DB)

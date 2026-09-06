# C1 cutover evidence — H1 executed 2026-09-06

Operator proxy: Glen (task t_9d567a79), per CONTRACT rule 7 / GATES.md H1
grant (Chad, #infra). Runbook: RUNBOOK-cutover.md §1–§6.

## Timeline (EDT / UTC-4)

| Time | Step | Result |
|---|---|---|
| 10:34 | §1.1 fresh dump | `/mnt/photos/backups/immich-pgdump-20260906T143422Z.sql.gz` (38 MB) |
| 10:35 | §1.2 freshness | restic=0, dbdump=0 |
| 10:36 | §1.4 images | both v3.1.0 images present (pre-pulled) |
| 10:36 | §1.5 DB facts | dbs postgres+immich; role immich; exts cube,earthdistance,pg_trgm,plpgsql,unaccent,uuid-ossp,vchord,vector |
| 10:36 | §1.3 baseline eval/build on bee | EVAL-OK, BASELINE-BUILD-OK |
| 10:37 | §2 window open | 2026-09-06T14:37:06Z, #infra notified |
| 10:38 | §3 cutover commit | 68e9272 (one-line import `./immich-quadlet.nix`) |
| 10:39 | §3b eval gate on bees | all values green (services.immich.enable=false, quadlet etc sources, uid 991/gid 993/nas-photos 1000, PG 17.11, redis immich) |
| 10:40 | §4 deploy (detached) | gen 4yzx5q3v…, "All hosts deployed" |
| 10:41–10:44 | first-boot migrations | FAILED → see incident 1 |
| 10:44 | ownership fix applied | 61 relations + 4 enums + 2 standalone seqs → immich |
| 10:46 | server restart | migrations resumed |
| 10:48 | second failure | functions still postgres-owned → fix 22 functions |
| 10:49 | server UP | ping pong, v3.1.0 |
| 10:52 | §5 verify run 1 | 16 pass / 2 fail (ml 500, album-add parse) |
| 10:53–10:58 | fixes | ML HOME=/cache; verify album-add array parse; commit 829ac14 |
| 10:59 | §4 redeploy | fix landed in /etc/containers/systemd |
| 11:00 | §5 verify run 2 (gate) | **18 pass / 0 fail / 0 skip, EXIT=0** |

## §5 gate — verify-immich.sh --mode upload --record (final run)

18/18 PASS (units ×2, image, ping, version, auth, albums, assets, db ×3,
record, ml, upload, album ×2, cleanup ×2). Baseline recorded:
albums=1, assets=4725 (`/var/tmp/immich-verify-state.json`).

## Deviations from the runbook (all within operator-proxy authority)

1. **DB ownership surgery (incident 1).** All 61 tables, 4 enums, 2 sequences,
   and 22 functions in `public` were owned by `postgres` (historical
   dump-restore as postgres). v3.1.0 migrations require ownership
   (`ALTER TABLE asset DROP COLUMN deviceAssetId` → 42501). Fixed by ALTER
   OWNER to `immich` (extension-owned objects excluded; column-linked
   sequences followed their tables). SQL: `owner-fix.sql` in this dir.
   Evidence: `table-owners.txt` (immich|61 after). Root cause is pre-existing,
   not caused by the cutover; §7.2's dump-restore path would reproduce it.
2. **ML HOME=/cache (incident 2).** First CLIP model download failed:
   image defaults HOME=/usr/src (root-owned), uid 991 cannot write
   ~/.config/.cache → "Permission denied". Fixed in
   `hosts/bees/immich-machine-learning.container` (commit 829ac14), deployed,
   ML restarted, smart search green.
3. **verify-immich.sh album-add parse.** v3.1.0 `PUT /albums/{id}/assets`
   returns an ARRAY; script expected an object map. The API call itself
   succeeded both runs. Fixed in commit 829ac14 (handles both shapes).
4. **loop-verify API key.** No Immich credential existed (checked Glen vault —
   no item; no env/agenix). Created a dedicated `loop-verify` API key via
   direct DB insert (sha256 digest, bytea — format verified against the
   v3.1.0 image source: `hashSha256(...).digest()` raw bytes). Scoped
   permissions: album.*/albumAsset.*/asset.read|upload|delete|view|statistics,
   timeline.read, session.create, user.read. Needed for rows 5/6/8/9/10
   (row 10 records the soak baseline). Token held only in
   `/tmp/c1-loop-verify-token` (root 0600) on bees for this run + soak use.

## Dump sha256

`8d7ddc3655e8a744b63192b61e1ba26f94d11526c1612e934a40f4734910b344  /mnt/photos/backups/immich-pgdump-20260906T143422Z.sql.gz`

## Files

units.txt, status.txt, podman-ps.txt, server-inspect.json, images.txt,
verify.json, pg-extensions.txt, server-journal-tail.txt, dump-sha256.txt,
owner-fix.sql, table-owners.txt

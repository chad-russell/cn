# RUNBOOK — Immich cutover (module → quadlet, 2.7.5 → v3.1.0) — H1

Board: `immich-loop` · Task: B2 → executed as C1 by the operator after H1.
Host: **bees** (10.10.0.6). Duration: ~30-45 min plus soak. Zero photo-data movement.

Read PLAN.md (decisions D1-D9), FACTS.md, CONTRACT.md first. This runbook is
the exact operator script; commands are copy-pasteable in order. Sections
marked `TODO-B1(...)` must be finalized from B1's dry-run output before H1.

Grounding facts baked in below (all verified 2026-09-06):

- The nixpkgs `services.immich` module OWNS postgres for immich: it sets
  `services.postgresql.enable`, `ensureDatabases=[immich]`,
  `ensureUsers` (user `immich`, DB ownership), **extensions `pgvector` +
  `vectorchord`, `shared_preload_libraries=["vchord.so"]`,
  `search_path='"$user", public, vectors'`**, and a `postgresql-setup
  ExecStartPost` that CREATEs/UPDATEs 7 extensions (`unaccent, uuid-ossp,
  cube, earthdistance, pg_trgm, vector, vchord`) in the immich DB. All of
  that evaporates when the module is disabled → the cutover commit MUST
  re-declare it (§3).
- Redis: the module's `services.redis.servers.immich` listens on a **unix
  socket** by default (`/run/redis-immich/redis.sock`, group `redis-immich`),
  NOT TCP. `redis-cli -s /run/redis-immich/redis.sock ping` is the probe.
  Whether the container uses the socket (volume-mount) or we switch to TCP
  is `TODO-B1(env-db-vars)`.
- pg_hba today: local socket = peer, `127.0.0.1/32` + `::1/128` = md5.
  The immich DB role password exists (module used a secretsFile); the
  container's connection strategy must be resolved in §1.5 / TODO-B1.
- Unit-file discriminator (live-verified): quadlet units have
  `SourcePath=/etc/containers/systemd/<x>.container` +
  `FragmentPath=/run/systemd/generator/…`; NixOS units are
  `/etc/systemd/system` symlinks into /nix/store with empty SourcePath.
- v3.1.0 API (from the shipped OpenAPI spec @ tag v3.1.0): ping →
  `{"res":"pong"}`; version → `{major,minor,patch,prerelease}`; login →
  **201** + `accessToken`; upload `POST /assets` (multipart:
  assetData/filename/fileCreatedAt/fileModifiedAt — deviceAssetId/deviceId
  are GONE in v3.1.0); search → `POST /search/metadata` and
  `/search/smart` (the old GET /search is gone); delete asset →
  `DELETE /assets {ids, force}`; album add → `PUT /albums/{id}/assets {ids}`.
- Deployment doctrine (26.05): builds/pushes take 5-8 min — start detached
  (`nohup … & disown`), poll from short calls. Never fire two deploys.

---

## 0. Preconditions (before anything)

- [ ] H1 granted: Chad said "go" in #infra (check GATES.md).
- [ ] B1 dry-run GREEN: sandbox stack on :3283/:3303 passed its checks and
      `docs/immich-loop/evidence/` has the dry-run evidence.
- [ ] All `TODO-B1` markers below resolved and this runbook finalized.
- [ ] Operator shell: bee → `ssh -o IdentitiesOnly=yes crussell@bees`
      (works BatchMode; `sudo -n` verified).

## 1. Pre-flight (bees, ~10 min)

### 1.1 Fresh DB dump (do NOT skip)

```bash
ssh bees  # = ssh -o IdentitiesOnly=yes crussell@10.10.0.6
sudo systemctl start immich-db-dump.service && systemctl status immich-db-dump.service --no-pager
DUMP=$(ls -1t /mnt/photos/backups/immich-pgdump-*.sql.gz | head -1); echo "$DUMP"
ls -la "$DUMP"                          # fresh timestamp, non-trivial size
zcat "$DUMP" | head -5                  # sane SQL header
zcat "$DUMP" | tail -5                  # completes (no mid-write truncation)
echo "$DUMP" > /tmp/cutover-dump-path   # referenced in §7
```

Record `sha256sum "$DUMP"` for the evidence bundle (§6). If the dump job
fails → STOP, fix it first (it is the rollback line of defense).

### 1.2 Restic freshness

```bash
sudo systemctl start freshness-bees-restic.service; echo "restic-freshness=$?"
sudo systemctl start freshness-immich-db.service;  echo "dbdump-freshness=$?"
```

Both must exit 0 (newest S3 snapshot < 36 h old; dump fresh). Optional belt:
`sudo systemctl start restic-backups-homelab-s3.service` for an extra
snapshot right now (runs minutes; only if the nightly is >24 h old).

### 1.3 Baseline eval gate (pre-commit sanity)

Author work happens in the board repo on bee (`~/loop/cn`); bees only pulls
and deploys. Prove the CURRENT loop/wip evals clean before layering the
cutover commit (fast fail on pre-existing breakage):

```bash
# on bee:
cd ~/loop/cn && git fetch origin && git checkout loop/wip && git pull
nix eval .#nixosConfigurations.bees.config.networking.hostName --raw   # -> bees
nix build .#nixosConfigurations.bees.config.system.build.toplevel --no-link && echo BASELINE-BUILD-OK
```

(The authoritative post-commit gate is §3b — run there after authoring.)

### 1.4 Image pre-pull (system podman store)

```bash
sudo podman pull ghcr.io/immich-app/immich-server:v3.1.0
sudo podman pull ghcr.io/immich-app/immich-machine-learning:v3.1.0
sudo podman images | grep immich    # both pinned tags present
```

(Pre-pull also proves registry reachability. If the quadlet uses a
`podman.image`/`Image=` tag identical to D1 this is instant.)

### 1.5 DB connection strategy (with B1's answers — TODO-B1(env-db-vars))

Facts to confirm from the dry-run and fill in before cutover:

- `TODO-B1(env-db-vars)`: exact env names the container uses for DB + Redis
  (v3 images use `DB_URL` incl. `?sslMode=disable` for remote PG; older-style
  `DB_HOSTNAME/DB_USERNAME/DB_PASSWORD/DB_DATABASE_NAME` still work). Note
  which one B1's env file uses.
- `TODO-B1(env-db-vars)`: password handling — env-file reference to the
  agenix-rendered secret on bees, never plaintext in the repo (CONTRACT #5).
- `TODO-B1(env-db-vars)`: redis over the unix socket (volume mount
  `/run/redis-immich` + `REDIS_SOCKET`) or TCP (set
  `services.redis.servers.immich.port`/`bind` accordingly in §3).
- Resolve DB name + user authoritatively (module defaults). The §1.5
  extension list IS the pre-cutover capture that check row 7 compares
  against — save the output (it also feeds §7.2's extension restore).

```bash
sudo -n -u postgres psql -Atc "select datname from pg_database where datistemplate=false"   # expect: postgres, immich
sudo -n -u postgres psql -Atc "select rolname from pg_roles where rolname='immich'"          # expect: immich
sudo -n -u postgres psql -d immich -Atc "select extname from pg_extension order by 1"        # vector, vchord, … (save this list!)
```

### 1.6 Sudoers smoke for the verify script's DB check

```bash
sudo -n -u postgres psql -Atc 'select 1' && echo SUDOERS-OK
```

(FACTS says verified; re-confirm — verify-immich.sh's `--mode db` uses it.)

## 2. Cutover window start

```bash
# ISO format: journalctl --since parses it (the compact 20260906T… form
# silently yields nothing — verified on bees/26.05)
date -u +%Y-%m-%dT%H:%M:%SZ | tee /tmp/cutover-start    # timestamp for evidence + journalctl
```

Notify #infra **from bees** (notify.sh execs `hermes send`, which exists on
bee only): `ssh bees 'bash ~/Code/cn/docs/immich-loop/scripts/notify.sh "H1 cutover starting — immich module → v3.1.0 quadlet on bees"'`

## 3. The cutover commit (exact contents) — author on bee

Author in the board repo on bee (`~/loop/cn`), commit to `loop/wip` (D5),
push, then gate on bees. One commit, three file changes, nothing else:

**a) `hosts/bees/configuration.nix`:**

1. imports list: replace `./immich.nix` with `./immich-quadlet.nix`
   (B1's file; deployable prod quadlet — 2283/3003, NFS mounts, uid-mapping
   per A2, `TODO-B1(final-quadlet-names)` for unit names).
2. DELETE the `systemd.services.immich-server.onFailure` override. After the
   module is disabled, a `systemd.services.*` entry would create a stub
   immich-server.service that SHADOWS the quadlet-generated unit — the exact
   caddy trap documented in this same file (see its comment block). The
   quadlet's OnFailure (if any) must come from a systemd.packages drop-in or
   inside the .container file (TODO-B1(final-quadlet-names): confirm B1 did
   one of these).

**b) `hosts/bees/immich.nix` (module file): disable, do NOT delete** (D9 —
it IS the rollback). Note its other content still applies while imported —
but since (a) removes the import, ALSO relocate these two surviving bits
into `immich-quadlet.nix` (they only merge when the module is imported):

- `users.groups.nas-photos = { gid = 1000; }` — keep the group declared so
  the gid never shifts (the container's NFS uid/gid mapping from A2
  references it).
- `nixpkgs.config.permittedInsecurePackages = [ "immich-2.7.5" ]` — keep
  through the soak ONLY if loop/wip still evals it (harmless); D2 removes
  it. Simplest correct move: move the permit into immich-quadlet.nix now,
  drop it in D2 with the module file.
- The `systemd.services.immich-server.serviceConfig.SupplementaryGroups`
  override is DELETED along with the onFailure in (a).2 — same stub trap.

Then the module disable itself:

```nix
   services.immich.enable = false;   # was true — cutover 2026-09-XX, H1
```

(and leave everything else in the file untouched).

**c) `hosts/bees/immich-quadlet.nix` (or the host config): RE-ADD the
surviving services the module used to own** — CRITICAL per PLAN risk:

```nix
   # ── Survives services.immich disablement (owned by the module before) ──
   services.postgresql = {
     enable = true;
     package = pkgs.postgresql_17;          # 26.05 default; pin explicitly
     ensureDatabases = [ "immich" ];
     ensureUsers = [{
       name = "immich";
       ensureDBOwnership = true;
       ensureClauses.login = true;
     }];
     extensions = ps: [ ps.pgvector ps.vectorchord ];
     settings = {
       shared_preload_libraries = [ "vchord.so" ];
       search_path = ''"$user", public, vectors'';
     };
     authentication = ''
       # same policy the module shipped (FACTS: socket=peer, loopback=md5)
       local all all peer
       host  all all 127.0.0.1/32 md5
       host  all all ::1/128      md5
     '';
   };
   services.redis.servers.immich = {
     enable = true;
     logLevel = "warning";
     # socket default; if the container needs TCP instead, set port/bind here
     # per TODO-B1(env-db-vars)
   };
```

Notes:
- `ensure*` only create; they never drop — running them against the existing
  DB is a no-op. The 7-extension ExecStartPost the module had is NOT
  re-declarable via plain services.postgresql; extensions already installed
  in the immich DB persist. After first switch, verify row 7 (ext list
  unchanged vs §1.5) — that's the guard. If any are missing:

```bash
   sudo -n -u postgres psql -d immich -c "CREATE EXTENSION IF NOT EXISTS \"<ext>\"; ALTER EXTENSION \"<ext>\" UPDATE;"
```
- `git diff origin/loop/wip` must show EXACTLY the three files: `hosts/bees/
  configuration.nix`, `hosts/bees/immich.nix`, `hosts/bees/immich-quadlet.nix`
  (the last carries B1's files arriving via B1's own commits — the cutover
  commit touches only config + module flag if B1's file is already on
  loop/wip; `git diff --cached --stat` in §3b shows the truth).

### 3b. Commit, push, and the eval gate on bees

```bash
# on bee:
cd ~/loop/cn
git add hosts/bees/configuration.nix hosts/bees/immich.nix hosts/bees/immich-quadlet.nix
git diff --cached --stat                # EXACTLY the three files
git commit -m "bees: immich cutover — disable module, enable v3.1.0 quadlet, re-add explicit PG+Redis"
git push origin loop/wip

# on bees — THE gate (module disabled but PG+Redis survive):
ssh bees
cd ~/Code/cn && git fetch origin && git checkout loop/wip && git pull
nix eval .#nixosConfigurations.bees.config.services.immich.enable                                  # false
nix eval .#nixosConfigurations.bees.config.services.postgresql.enable                              # true
nix eval .#nixosConfigurations.bees.config.services.postgresql.package.name                        # postgresql-17.x
nix eval .#nixosConfigurations.bees.config.services.postgresql.ensureDatabases                     # ["immich"]
nix eval .#nixosConfigurations.bees.config.services.postgresql.settings.shared_preload_libraries   # ["vchord.so"]
nix eval .#nixosConfigurations.bees.config.services.redis.servers.immich.enable                    # true
nix build .#nixosConfigurations.bees.config.system.build.toplevel --no-link -vL && echo BUILD-OK
```

## 4. Deploy (from bees, detached pattern)

```bash
# on bees (continuing from §3b):
nohup nix run .#deploy -- bees > /tmp/deploy-bees-cutover.log 2>&1 & disown
# poll (from any short ssh session; never start a second deploy):
pgrep -af 'nix run .#deploy' || echo "deploy finished"
tail -5 /tmp/deploy-bees-cutover.log
nixos-version
readlink /run/current-system      # == newest /nix/var/nix/profiles/system-*-link
systemctl is-active postgresql redis-immich   # must both be active
```

First switch after a 25.11→26.05-style transition may print a benign
dbus-broker reload error + exit 4 — NOT expected here (fleet already on
26.05); treat any exit != 0 seriously: check the log before continuing.

Post-switch, immediately:

```bash
sudo systemctl daemon-reload
systemctl list-units 'immich*' --all --no-pager   # write down the EXACT server + ML unit names
SERVER_UNIT=<from list-units>                     # export for §5/§6 commands
# quadlet units live under /run/systemd/generator (like caddy) — if an
# expected unit is missing: ls /etc/containers/systemd/ && systemctl daemon-reload
```

v3 server runs DB migrations on first start — expect a slow first boot
(minutes); watch: `journalctl -u "$SERVER_UNIT" -f` until the server
reports listening, or `sudo podman logs <container>`.

## 5. Verification checklist (gate: every line before H1 is done)

Run order matters; the script does rows 1-10 automatically:

```bash
# on bees, from the loop/wip checkout (script landed with the cutover commit):
cd ~/Code/cn
sudo -E ./scripts/verify-immich.sh --mode upload --record
```

| # | Check | Pass condition | Script section |
|---|-------|----------------|----------------|
| 1 | Unit names active | server + ML quadlet units `active`, and `immich-server.service` either gone or has `.container` SourcePath | units |
| 2 | Containers pinned | `podman inspect` shows `ghcr.io/immich-app/*:v3.1.0` | image |
| 3 | API up | `GET /server/ping` → 200 `{"res":"pong"}` | ping |
| 4 | Version | `/server/version` → major.minor.patch = 3.1.0 | version |
| 5 | Login smoke | API-key or session login OK (201 + token) | auth |
| 6 | Browse counts | `/albums` n albums + `/assets/statistics` total ≥ sanity floor | albums/assets |
| 7 | DB extensions intact | psql list from the immich DB matches the §1.5 capture | db |
| 8 | Upload smoke | asset upload → add to `loop-verify-*` album → delete both | upload |
| 9 | ML responds | `POST /search/smart` 200 (CLIP pipeline) | ml |
| 10| Baseline recorded | state file written for soak drift checks | record |

Exit 0 = gate passed. Any FAIL → §6 capture + §7 rollback decision.

Manual bits the script does not own:
- **Web UI spot-check** (human eyes): `https://photos.crussell.io` loads,
  login, timeline thumbnails render, one album opens. (Gateway route
  untouched by design — D4.)
- **Upload from a phone** if convenient during soak (real-world client).
- Caddy: NOT reconfigured; if 2283 behaves oddly from outside, check
  `systemd-caddy` proxy upstream is still `10.10.0.6:2283` (it must be).

## 6. Evidence capture (during/after verification, before closing H1)

```bash
# on bees:
E=/tmp/immich-cutover-evidence; mkdir -p "$E"
systemctl list-units 'immich*' --all --no-pager                 > $E/units.txt
systemctl status "$SERVER_UNIT" "$ML_UNIT" --no-pager           > $E/status.txt  # names from §4
sudo podman ps -a --filter name=immich                          > $E/podman-ps.txt
sudo podman inspect <server-container>                          > $E/server-inspect.json 2>/dev/null || true
sudo podman images | grep immich                                > $E/images.txt
cd ~/Code/cn && sudo -E ./scripts/verify-immich.sh --json       > $E/verify.json 2>&1 || true
sudo -n -u postgres psql -d immich -Atc 'select extname from pg_extension order by 1' > $E/pg-extensions.txt
journalctl -u "$SERVER_UNIT" --since "$(cat /tmp/cutover-start)" --utc --no-pager | tail -200 > $E/server-journal-tail.txt
sha256sum "$(cat /tmp/cutover-dump-path)"                       > $E/dump-sha256.txt
```

Then pull the bundle back to bee and commit + notify (from bee — hermes
lives there):

```bash
# on bee:
mkdir -p ~/loop/cn/docs/immich-loop/evidence/cutover
scp -r -o IdentitiesOnly=yes bees:/tmp/immich-cutover-evidence/* ~/loop/cn/docs/immich-loop/evidence/cutover/
cd ~/loop/cn && git add docs/immich-loop/evidence/cutover && git commit -m "immich-loop: H1 cutover evidence" && git push origin loop/wip
bash docs/immich-loop/scripts/notify.sh "H1 cutover VERIFIED (v3.1.0 on :2283, upload+ML green, baseline recorded) — soak starts"
```

Then update GATES.md: H1 resolved, soak start timestamp (operator).

## 7. Rollback (exact commands)

Decision inputs: web unusable after migration churn, data-looking-wrong,
or the server won't start at all. Photos are untouched by construction (D7).
The DB is the only thing v3 mutated.

### 7.1 Generation rollback (first move, gets module 2.7.5 back)

```bash
ssh bees
nix-env --profile /nix/var/nix/profiles/system --list-generations | tail -5   # identify pre-cutover gen N
sudo nixos-rebuild --rollback switch            # rolls to previous gen
# if nixos-rebuild rollback is unavailable/manual:
#   sudo nix-env --profile /nix/var/nix/profiles/system --rollback
#   sudo /run/current-system/bin/switch-to-configuration switch
systemctl is-active immich-server immich-machine-learning postgresql redis-immich
curl -s http://127.0.0.1:2283/api/server/version    # 2.7.5 again
```

### 7.2 If the module (2.7.5) won't start against the v3-migrated DB

Restore the pre-cutover dump (§1.1 path in /tmp/cutover-dump-path):

```bash
DUMP=$(cat /tmp/cutover-dump-path)   # /mnt/photos/backups/immich-pgdump-<ts>.sql.gz
sudo systemctl stop immich-server immich-machine-learning    # if running
sudo -n -u postgres psql -c "DROP DATABASE immich;"
sudo -n -u postgres psql -c "CREATE DATABASE immich OWNER immich;"
# extensions first (dump assumes they exist), then data:
sudo -n -u postgres psql -d immich -c '
  CREATE EXTENSION IF NOT EXISTS "vector"; CREATE EXTENSION IF NOT EXISTS "vchord";
  CREATE EXTENSION IF NOT EXISTS "unaccent"; CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
  CREATE EXTENSION IF NOT EXISTS "cube";    CREATE EXTENSION IF NOT EXISTS "earthdistance";
  CREATE EXTENSION IF NOT EXISTS "pg_trgm";'
zcat "$DUMP" | sudo -n -u postgres psql -d immich -v ON_ERROR_STOP=0 2>&1 | tail -20
sudo systemctl start immich-server
curl -s http://127.0.0.1:2283/api/server/version && curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:2283/api/server/ping
```

(Match the §1.5 pre-cutover extension list exactly — that capture is
authoritative; trim the CREATE list if something wasn't installed.)

### 7.3 Re-enable the module declaratively (if rollback needs a deploy)

The cutover commit is on loop/wip; revert it rather than hand-editing:

```bash
# on bee:
cd ~/loop/cn && git checkout loop/wip && git pull
git revert <cutover-commit-sha>       # restores immich.nix import + enable=true
git push origin loop/wip
# then deploy exactly as §4 from bees, and re-verify rows 1,3,5,6 against module 2.7.5
# (run verify-immich.sh with IMMICH_EXPECT_VERSION=2.7.5 to allow the old version)
```

If git history is unavailable for any reason, manual equivalent: edit
`hosts/bees/immich.nix` → `services.immich.enable = true;`, restore the
`./immich.nix` import in configuration.nix, commit "bees: rollback —
re-enable services.immich (H1 aborted)", deploy as §4.

### 7.4 Post-rollback

- `bash docs/immich-loop/scripts/notify.sh "H1 cutover ROLLED BACK — module 2.7.5 restored, DB from <dump-ts>"`
- GATES.md: H1 back to pending; write a failure note in the log section.
- The cutover branch keeps the commit for post-mortem; do not delete.

## 8. After success: soak (D-phase pointer)

- Baseline already recorded by §5 (verify-immich.sh --record).
- Watchdog + nightly freshness checks keep running; `verify-immich.sh`
  gates the soak (no FAIL for ≥7 clean days → ask Chad for H2).
- B1 sandbox cleanup: ensure `/mnt/photos/.loop-sandbox/` and the
  `immich_dryrun` DB are gone (`TODO-B1`: B1 confirms in its evidence).
- Post-soak cleanup diff (D2 task) removes immich.nix + the insecure permit.

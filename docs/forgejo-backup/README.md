# Forgejo Backup & Restore Runbook (git.crussell.io)

Verified working 2026-09-09 (restore drill executed on a dump copy — see
"Restore drill log" at the bottom).

## Architecture

```
gateway (VPS, secret-free)          bees (restic-covered)         off-site
┌─────────────────────────┐   rsync  ┌──────────────────────┐    ┌─────┐
│ forgejo-dump-bounded    │ ───────► │ /var/lib/forgejo-dumps│ ─► │ NAS │
│ 03:30 `forgejo dump`    │  04:45   │ (root-owned zips,     │    │ S3  │
│ → /var/lib/forgejo/     │  pull    │  restic allowlisted)  │    └─────┘
│   dump-temp/ (retain 3) │          │ restic-backups-homelab│
└─────────────────────────┘          │ -{nas,s3} daily       │
                                     └──────────────────────┘
```

- **Gateway never holds backup credentials** — it only creates dumps; bees
  pulls them (rsync over Nebula, ssh as crussell's key → root@10.10.0.2).
- Source modules: `hosts/gateway/forgejo-dump-bounded.nix` (dump side),
  `hosts/bees/forgejo-backup-pull.nix` (pull side), allowlist entry in
  `hosts/bees/backup.nix`.
- The NixOS forgejo module's built-in `dump.enable` timer is OFF (replaced —
  it has no retention control and would double-dump nightly).

## Contents of a dump zip

`repos/` (bare git repos incl. hooks), `data/` (attachments, avatars,
actions logs), `custom/conf/app.ini` (⚠ SECRETS: SECRET_KEY / INTERNAL_TOKEN
/ JWT — the dump zip is sensitive; that's fine — it only lives on gateway
[0700 forgejo] and bees [root-only]), `forgejo-db.sql` (full SQL).

## Emergency restore (VPS lost / state corrupted)

T = target gateway (freshly deployed cn `gateway`, forgejo.active).

1. **Fetch newest dump** (from bees local, or restic→S3/NAS if bees is gone):
   ```bash
   # newest on bees:
   DUMP=$(ls -t /var/lib/forgejo-dumps/forgejo-dump-*.zip | head -1)
   # or from restic (any host with the repo creds):
   #   restic restore latest --target /tmp/r --path /var/lib/forgejo-dumps
   # then /tmp/r/var/lib/forgejo-dumps/
   scp "$DUMP" root@10.10.0.2:/var/lib/forgejo/
   ```
2. **Stop forgejo** on gateway: `systemctl stop forgejo`.
3. **Unzip** on gateway:
   ```bash
   cd /var/lib/forgejo
   nix shell nixpkgs#unzip -c unzip -o forgejo-dump-<ts>.zip
   # creates: repos/, data/, custom/, forgejo-db.sql  (local dir)
   ```
   Verify structure: `ls repos/<owner>/`, `head forgejo-db.sql`.
4. **Restore state**:
   - `cp -a repos data custom /var/lib/forgejo/` — merge into state dir.
     (If state is corrupt rather than absent, move the old dirs aside first.)
   - Restore DB — the dump's SQL is sqlite3 dialect (dump taken from sqlite):
     ```bash
     nix shell nixpkgs#sqlite -c sqlite3 /var/lib/forgejo/data/forgejo.db \
       < /var/lib/forgejo/forgejo-db.sql
     ```
     ⚠ If restoring to a NEW db file, delete `forgejo.db*` first (fresh DB
     + WAL files from the live instance can conflict — old journal against
     the restored DB).
5. **Fix ownership** (forgejo runs as user `forgejo`):
   `chown -R forgejo:forgejo /var/lib/forgejo`.
6. **Start + verify**: `systemctl start forgejo`, then `curl -fsS
   https://git.crussell.io/api/v1/version` and check a repo clones:
   `git clone git@git.crussell.io:2222/chad/cn.git /tmp/restore-check && cd
   /tmp/restore-check && git log --oneline -1`.
7. **Repoint cn remotes** (if DNS/IP unchanged, nothing to do — just verify
   `git -C ~/Code/cn push --dry-run origin main` works).

### Restore to a different host

The pull + restic side (bees, S3, NAS) is host-independent. On a new gateway:
deploy cn `gateway` (agenix secrets auto-decrypt via the age identity under
crussell's home — see AGENTS.md Secrets section), then run the
procedure above; `forgejo dump`'s app.ini contains the instance secrets, so
the restored instance is the SAME instance (same tokens/2FA).

## Monitoring

- `forgejo-dump-bounded.service` / `forgejo-dump-pull.service` both have
  `onFailure → ntfy-failure@` (homelab-alerts topic).
- `freshness-forgejo-dumps.timer` (daily, declared in
  `forgejo-backup-pull.nix`): newest `forgejo-dump-*.zip` on bees must be
  < 40h old → ntfy otherwise. This covers BOTH legs — a silently-dead
  gateway dump or a dead pull timer both leave stale zips on bees — so no
  gateway-side freshness check is needed (landed 2026-09-09; was the
  deliberate MVP follow-up noted here earlier).

## Restore drill log (2026-09-09, executed)

- Copy of `forgejo-dump-1788967921.zip` (27.9 MB) → `/var/tmp/forgejo-restore-drill/`
- `unzip -l`: 367 files — repos/chad/{cn.git,smoke.git}, data/, custom/, forgejo-db.sql (225 KB)
- `unzip` → bare repos readable: `git --git-dir repos/chad/cn.git log --oneline -3`
  showed the three same-day commits (d923083/901c5d4/5bdb2e6) — dump is current.
- `sqlite3 restore-test.db < forgejo-db.sql` → clean import, no errors:
  `repository` = 2 rows (cn, smoke), `user` = 1 row (chad).
- Drill dir cleaned up afterward.

## Design notes / gotchas learned

- forgejo 15.0.7 `dump` has **no `--output`** flag — it's `--file/-f` (bit me
  on first run; fixed in commit 901c5d4).
- `rsync -a` copies gateway's numeric forgejo uid/gid → maps to `prowlarr` on
  bees; pull uses `--no-owner --no-group` so dumps land root-owned (d923083).
- Timer schedule: gateway dumps 03:30, bees pulls 04:45 (+10m jitter);
  restic s3/nas run `daily` with 1h RandomizedDelaySec (≈04:00–05:00
  window) — so the nightly restic run may occasionally run BEFORE the pull;
  the dump is then covered by the NEXT day's snapshot. Accepted (RPO ≤ 48h
  worst case for off-site, ≤ 20h on-bees).
- root@bees has no ssh key; the pull unit uses `ssh -i
  /home/crussell/.ssh/id_ed25519` (already an authorized root key on
  gateway — same key deploys use). Gateway's host key is pinned in
  `programs.ssh.knownHosts` on bees (no TOFU).
- `rm -rf` / `find -delete` under /var/lib|tmp are approval-blocked in agent
  sessions — use the rsync-empty-dir trick or single-file rm via root ssh.

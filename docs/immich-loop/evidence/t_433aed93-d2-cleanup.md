# Evidence — t_433aed93 (D2: post-soak cleanup diff)

Prepared early per operator note (2026-09-06): pure git work on loop/wip, no
live system touched. Cutover artifacts B1 committed mid-run (quadlets wired in
`immich-quadlet.nix`, OnFailure already in `immich-server.container`), so this
diff composes with them rather than restructuring.

## What the diff does

| Change | File |
|---|---|
| Delete module-era config wholesale (services.immich, nas-photos group, SupplementaryGroups, redis logLevel, `permittedInsecurePackages = [ "immich-2.7.5" ]`) | `hosts/bees/immich.nix` (deleted) |
| Delete old file; content carried over | `hosts/bees/immich-backup.nix` (deleted) |
| NEW: native-side survivors — postgres + redis-immich re-declaration (RUNBOOK §3c, runbook-exact) + immich-db-dump service + timer + freshness check (byte-identical body to immich-backup.nix, verified by diff) | `hosts/bees/immich-native.nix` (new) |
| Import swap (immich.nix + immich-backup.nix → immich-native.nix) + remove the `systemd.services.immich-server.onFailure` override (would write a stub unit shadowing the podman-system-generator output for a quadlet — same trap as the caddy comment directly below it); alerting already landed in `immich-server.container` `[Unit]` (commit 95e80f1) | `hosts/bees/configuration.nix` |
| Sandbox-cleanup note (post-H2 operator checklist) | `docs/immich-loop/CONTRACT.md` |

## Why immich-native.nix (not just the dump)

First flake-check run failed with `The option 'services.postgresql.package'
was accessed but has no value defined` — PLAN's predicted hazard: with the
module gone, nothing enables services.postgresql on bees, and the dump unit
reads `config.services.postgresql.package`. The runbook's §3c re-declaration
therefore must live in an IMPORTED file pre-cutover (importing
immich-quadlet.nix early would itself perform the cutover wiring).
The re-declaration is runbook-exact; `ensure*` only create (no-op against
the existing DB), `pgvector` + `vectorchord` extensions, peer/md5 auth unchanged,
redis-immich socket + logLevel warning. Pre-cutover, live bees still runs the
module-era generation; the immich-native.nix tree (module gone, native
re-declaration + id pins in) is the post-H2 cleanup deploy's content, gated
behind H2 — it is not live until then, and the module never coexists with it
in a single deployment.

## Verification commands (output excerpts)

```
$ grep -rn 'permittedInsecurePackages' --include='*.nix' .
./hosts/bees/immich.nix:31:  nixpkgs.config.permittedInsecurePackages = [ "immich-2.7.5" ];
$ grep -rn 'nas-photos' --include='*.nix' .
./hosts/bees/immich.nix:19,20,22          # (only occurrences — both files deleted)
# after the diff:
$ grep -rn 'permittedInsecurePackages\|immich-2.7.5' --include='*.nix' .
(no matches → permit entry landed nowhere)
$ grep -rn 'nas-photos' --include='*.nix' .
hosts/bees/immich-native.nix   # exactly one hit — the gid-1000 reservation pin

$ git show HEAD:hosts/bees/immich-backup.nix > /tmp/orig.nix && diff -u /tmp/orig.nix hosts/bees/immich-native.nix
→ dump/timer/freshness bodies identical; native file adds the provenance
  comment, the id-reservation block, and the §3c PG+redis re-declaration

$ nix shell nixpkgs#treefmt nixpkgs#nixfmt-classic -c treefmt --ci
traversed 464 files / emitted 46 / formatted 46 files (0 changed) — clean

$ nix flake check
→ see below
```

## nix flake check

Ran from bee (dev host, not the deploy origin — eval only, no deploy, per
CONTRACT rule 1):

```
checking NixOS configuration 'nixosConfigurations.bees'...
building '/nix/store/...-unit-immich-db-dump.service.drv'...
building '/nix/store/...-unit-immich-db-dump.timer.drv'...
building '/nix/store/...-unit-freshness-immich-db.service.drv'...
building '/nix/store/...-unit-freshness-immich-db.timer.drv'...
building '/nix/store/...-unit-postgresql.service.drv'...
building '/nix/store/...-unit-redis-immich.service.drv'...
building '/nix/store/...-pg_hba.conf.drv'...
building '/nix/store/...-nixos-system-bees-26.05.20260905.6713828.drv'...
running 365 flake checks...
all checks passed!            (flake-check-exit=0)
```

(Note: run 1 failed on the untracked-file guard — `git add` the new file
first; run 2 failed with `services.postgresql.package` undefined — the
module-removal hazard that produced immich-native.nix; run 3 green.)

## AGENTS.md — blocked write, hunks ready

The AGENTS.md edit was blocked by the agent-instruction-file protection layer
(approval prompt timed out — headless run). Hunks below are ready to apply
post-H2 (or by the operator now); they describe the POST-cutover state:

Hunk 1 — repo tree (~line 42):

```diff
-│   │   ├── immich.nix + immich-backup.nix
+│   │   ├── immich-quadlet.nix   # Immich quadlets (server + ML containers)
+│   │   ├── immich-native.nix    # native PG + redis-immich + db dump + freshness
```

Hunk 2 — bees source files list (~line 250):

```diff
-- `hosts/bees/immich.nix` + `hosts/bees/immich-backup.nix` — Immich server + ML
+- `hosts/bees/immich-quadlet.nix` — Immich server + ML quadlets (wired at cutover)
+- `hosts/bees/immich-native.nix` — native postgres + redis-immich + nightly pg_dump + freshness check
```

Hunk 3 — live systemd services (~lines 272-275):

```diff
-- `immich-server.service` — `2283`
-- `immich-machine-learning.service`
+- `immich-server.service` — podman quadlet, `2283` (host network)
+- `immich-machine-learning.service` — podman quadlet, `127.0.0.1:3003`
 - `postgresql.service` — Immich DB
 - `redis-immich.service`
```

(Note: the live-services list is only true after the cutover deploy; it
matches PLAN's Definition of Done "module removed, docs updated".)

## Notes / decisions

- The survivors live in `hosts/bees/immich-native.nix` rather than folding
  into `immich-quadlet.nix`: B1's cutover file was committed mid-run by a
  concurrent worker (my earlier same-path draft was overwritten — conceded;
  see the hotspot comment on the card). The separate native file also keeps
  the imported pre-cutover state self-sufficient: importing
  immich-quadlet.nix early would itself perform the cutover wiring.
- uid/gid reservations: landed (round-2 rework, reviewer blockers #1/#2)
  in `hosts/bees/immich-native.nix` — `users.users.immich.uid = 991`
  (+ isSystemUser, group immich), `users.groups.immich.gid = 993`,
  `users.groups.nas-photos.gid = 1000`. The nixpkgs module declared the
  user/group with auto-allocated ids (mutableUsers persisted 991/993);
  with the module gone, the pins prevent re-allocation drift — the
  quadlets hardcode User=991:993 and PG peer auth + NFS ownership are
  numeric. redis-immich (gid 992) stays module-held via
  services.redis.servers.immich below. Verified by eval:
  uid=991, gid=993, nas-photos gid=1000 all green.
- Bees firewall: `networking.firewall.enable = false` (configuration.nix:137),
  so dropping the module's `openFirewall = true` changes nothing.
- Sandbox cleanup checklist added to CONTRACT.md (D2 item). Requires SSH to
  bees to VERIFY (read-only); not executed in this run — nothing was deployed.
- Rollback story unchanged (PLAN D9): gen rollback restores the module; this
  diff only lands with the post-H2 cleanup deploy.

## Round-2 rework (run 7, reviewer blockers from comment 8)

Changes on top of 9a9790a, all pure git work on loop/wip — live bees
untouched (module-era generation still running):

1. **Blocker #1 + #2 — id reservations pinned** in
   `hosts/bees/immich-native.nix`: `users.users.immich.uid = 991`
   (isSystemUser, group immich), `users.groups.immich.gid = 993`,
   `users.groups.nas-photos.gid = 1000`. The nixpkgs module declared the
   user/group with auto-allocated ids (mutableUsers persisted 991/993
   live); with the module gone the pins keep the ids stable — the
   quadlets hardcode User=991:993, and PG peer auth + NFS ownership are
   numeric. redis-immich (gid 992) stays declared by
   services.redis.servers.immich in the same file, so its mutableUsers
   reservation persists; no pin needed.
2. **Blocker #3 — RUNBOOK-cutover.md rewritten for the post-D2 branch**:
   §3 header now names the D2 pre-state (immich.nix deleted,
   immich-native.nix imported, quadlet files committed but unwired);
   §3a = one-line import add (nothing to replace); §3b git-add list is
   the single configuration.nix, commit msg updated, eval gate gains
   quadlet-etc-source + id-pin assertions (with the note that
   services.immich stays evalable via the nixpkgs base module list);
   §7.3 = revert cutover commit AND 9a9790a together (newest first),
   with the ordering rationale + manual-equivalent fallback;
   §8's D2 bullet notes the diff has landed.
3. **Nit #4 — evidence paths fixed**: both `immich-db-dump.nix`
   references corrected to `immich-native.nix` (verification commands
   now reproduce); false "TODO in the cutover path" claim replaced with
   the landed pins; stale "module coexists during soak" rationale
   replaced with the correct gating story (never coexist in one
   deployment; native tree activates only at the post-H2 deploy).
4. Also resolved §1.5's TODO-B1(env-db-vars) block from B1's committed
   `immich-server.container` (DB_URL socket peer-auth, REDIS_SOCKET,
   GroupAdd=992 — no secret material), so the runbook is H1-final.

Verification (this round, real output):

```
$ nix shell nixpkgs#treefmt nixpkgs#nixfmt-classic -c treefmt --ci
formatted 46 files (0 changed) in 657ms            # clean

$ grep -rn 'permittedInsecurePackages\|immich-2\.7\.5' --include='*.nix' .
(no matches → permit still lands nowhere)

$ grep -rn 'nas-photos' --include='*.nix' .
hosts/bees/immich-native.nix  # header comment ×2 + the gid-1000 pin — intended

$ nix flake check
building '.../nixos-system-bees-26.05.20260905.6713828.drv'...
all checks passed!                                 # FLAKE-CHECK-EXIT=0
```

Live bees untouched (read-only SSH confirms module-era generation).

## Round-3 rework (run 9, reviewer blocker from comment 11)

Docs-only fix, no Nix touched — RUNBOOK §7.3's revert chain documented as
an attended sequence with the expected conflict made explicit.

The round-2 review EXECUTED §7.3 in a scratch worktree at ed955d6 and
found revert #2 (9a9790a) stops with CONFLICT (modify/delete) on
`hosts/bees/immich-native.nix` + this evidence file — 9cc25fe modified
both after 9a9790a created them. Round-2's §7.3 implied the chain ran
unattended; it does not.

Fix applied to RUNBOOK-cutover.md §7.3:

1. The revert command block now carries the resolution inline: an
   `# EXPECT:` comment naming the two conflicted paths and why, then
   `git rm hosts/bees/immich-native.nix
   docs/immich-loop/evidence/t_433aed93-d2-cleanup.md` +
   `git revert --continue --no-edit` (the revert's intent IS their
   deletion — accept it and continue).
2. The ordering paragraph no longer claims unattended completion: it now
   says revert #1 lands clean, revert #2 stops at the expected
   modify/delete conflict, and the git rm + --continue lines resolve it.

Verification (this round, re-executed independently before patching —
script /tmp/r3-repro.sh, scratch worktree at ed955d6):

```
sim cutover: 210f430
--- revert 1: cutover --- CLEAN
--- revert 2: 9a9790a ---  CONFLICT as reviewer claimed; status:
UD docs/immich-loop/evidence/t_433aed93-d2-cleanup.md
UD hosts/bees/immich-native.nix        # (+ M CONTRACT.md, M configuration.nix,
                                        #  A immich.nix + immich-backup.nix staged)
--- resolve: git rm conflicted paths + revert --continue --- REVERT-CONTINUE-OK
--- post-rollback tree ---
hosts/bees/immich.nix + immich-backup.nix restored, immich-native.nix gone,
configuration.nix imports ./immich.nix + ./immich-backup.nix,
immich.nix:31 permittedInsecurePackages = [ "immich-2.7.5" ] restored
bees EVAL-OK, services.immich.enable = true
```

The exact `git revert --continue --no-edit` form was separately verified
(second scratch worktree): completes cleanly, commit subjects
`Revert "bees: immich cutover …"` + `Revert "immich-loop D2: …"`.

Reverting 9cc25fe in the chain instead was considered and rejected (per
reviewer): it would leave ed955d6's §3-preamble line stale in the
runbook; the git-rm note matches the already-listed expected effects.


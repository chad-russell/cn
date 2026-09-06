# Worker Contract — immich-loop board

Binding rules for all workers on this board. Read PLAN.md first; it is the
constitution. This file governs blast radius and behavior.

## Repo & branch

- Repo: `~/loop/cn` (clone of chad-russell/cn). ALL work lands on `loop/wip`
  (push allowed). NEVER touch `main` (no merges, no pushes, no rebases onto it).
- Workers commit to `loop/wip` with clear messages; no force-push.

## Blast radius (hard rules)

1. NO `nix run .#deploy` / `nixos-rebuild` on ANY host — deploy is operator-only.
2. NO `systemctl stop/start/restart` of PRODUCTION services on bees
   (immich-server, immich-machine-learning, postgresql, redis-immich, caddy).
   Exception: the dry-run sandbox units you create yourself
   (`immich-dryrun-*`) and pulling container images via podman.
3. NO touching `/mnt/photos` contents beyond `.loop-sandbox/` (see below) —
   never list/read/modify outside it.
4. NO modifying `services.immich`, `services.postgresql`, or any host config
   that would take effect on next deploy WITHOUT an explicit task contract
   saying so. Dry-run quadlets go in a self-contained new file
   (`hosts/bees/immich-quadlet.nix` + `.container` files) that is NOT
   imported by the live configuration.
5. NO secrets in the repo. DB passwords go in agenix templates or the
   operator-runbook — never committed plaintext.
6. `blocked = ping, never guess`. Block the card, fire
   `docs/immich-loop/scripts/notify.sh`, stop.
7. **C1 exception (D6-amended, 2026-09-06):** the cutover card executes
   RUNBOOK-cutover.md §1–§6 on bees as *operator proxy* — Chad's chat grant
   (GATES.md H1 log) is the authority. During C1 only, rules 1–2 above are
   lifted for bees + immich services exactly per the runbook, deviating only
   to follow §7 rollback. Deploys to other hosts remain operator-only. H2
   (post-soak cleanup) stays a human gate.

## Dry-run sandbox (the only place workers touch bees)

- Sandbox root: `/mnt/photos/.loop-sandbox/` — create it, work in it, remove it when done.
- Dry-run server port 3283, ML port 3303 (prod = 2283). Container names `immich-dryrun-server` / `immich-dryrun-ml`.
- The dry-run DB: **new scratch DB** `immich_dryrun` created in the NATIVE
  postgres (worker MAY create/drop this one DB; nothing else in PG).
 `CREATE DATABASE immich_dryrun` needs superuser — if `sudo -u postgres` on bees is unavailable to you, block with a precise ask.
- Dry-run containers must NOT connect to the `immich` prod DB. Env must point at `immich_dryrun`.
- **Sandbox cleanup (task D2 / post-H2):** before the board closes, verify the
  sandbox is gone: `ssh bees 'ls -d /mnt/photos/.loop-sandbox'` should fail and
  `sudo -u postgres psql -lt` should show no `immich_dryrun`. If the dry-run
  worker left anything behind, the OPERATOR removes it
  (`sudo rm -rf /mnt/photos/.loop-sandbox`, drop DB `immich_dryrun`, and
  `systemctl stop/disable/reset-failed immich-dryrun-*` if those units were
  installed) — workers may not touch production systemd or PG beyond the
  scratch DB.

## Evidence

Every task writes evidence (commands + output) to
`docs/immich-loop/evidence/<task-id>-<slug>.md` in the same commit as the work.

## Notify

`bash docs/immich-loop/scripts/notify.sh "<message>"` → posts to Discord #infra.
Use for: blocked, milestone done, review-requested. Keep messages short.

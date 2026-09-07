# Immich → Podman Quadlet Migration — PLAN

**Board:** `immich-loop` · **Repo:** cn @ `loop/wip` · **Operator:** Glen (default profile)
**Created:** 2026-09-06 · **Status:** ACTIVE

## Goal

Migrate Immich on **bees** from the NixOS module (`services.immich`) to podman
quadlets (matching jellyfin/linkding/papra/etc), upgrading 2.7.5 → **v3.1.0**
(latest stable) in the same move. Photos remain on NFS `/mnt/photos`; the
Postgres DB and Redis stay NATIVE in phase 1. Zero photo-data movement, zero
ingress changes, full rollback path, one-week soak before cleanup.

## Locked decisions (workers never re-litigate)

| # | Decision |
|---|---|
| D1 | Target = upstream images `ghcr.io/immich-app/immich-server:v3.1.0` + `immich-machine-learning:v3.1.0` (pin exact tag, never `:latest` or `:release`) |
| D2 | Postgres (native, immich DB) + Redis (`redis-immich.service`) stay host-level in phase 1; containers reach them over host network |
| D3 | Final ports = 2283 (server) — same as today; dry-run uses 3283/3303 to avoid collision |
| D4 | Caddy routes unchanged: `photos.crussell.io` (gateway) already → `10.10.0.6:2283` |
| D5 | All worker code lands on branch `loop/wip` in cn — never main |
| D6 | NixOS deploys, service stops/starts on bees beyond the dry-run sandbox, and anything touching the immich DB = OPERATOR ONLY (human gate) |
| D7 | Photo data stays at `/mnt/photos` (NFS, read+write); no copies, no re-upload |
| D8 | DB/Redis auth: discover the LIVE auth mode from bees (peer/trust/password) before writing env; never guess |
| D9 | Rollback = re-enable `services.immich` (module stays in repo, disabled, through the soak); old gen is one `nixos-rebuild --rollback` away |

## Human gates

| # | Gate | Owner | Unblocks |
|---|---|---|---|
| H1 | Cutover window: Chad says "go" in #infra (prefer a low-use evening) | Chad | C1 |
| H2 | Post-soak cleanup deploy after ≥7 clean days | Chad | D2 |

## Phases

- **A — Research (workers):** upstream v3.1.0 stack reference (env/volumes);
  NFS uid-mapping proof (container writes as the immich uid).
- **B — Build (workers):** quadlet files + env file + dry-run on bees
  (scratch ports, sandbox dirs, zero prod interference); cutover runbook +
  verification script.
- **C — Cutover (operator):** H1 → Glen executes the runbook (deploy,
  verify, evidence to #infra).
- **D — Soak & cleanup:** 7-day watch; cleanup diff (module removal,
  insecure-permit drop); H2 → final deploy, board closed.

## Risks & rollbacks

- **2.7.5 → 3.x major jump:** app-level migrations run on first start.
  Mitigation: pre-cutover pg_dump (fresh, verified) + restic snapshot; the
  dump is restorable into native PG in minutes. Web/API breakage for
  third-party tools is expected-but-acceptable (family instance).
- **Disabling the NixOS module may drop PG/Redis units** (module may own
  `services.postgresql` + `redis.servers.immich`). Cutover commit must
  RE-ADD them explicitly (package pin postgresql_17) so the DB never
  disappears. Workers verify this in the dry-run analysis; operator
  verifies with `nix eval` before deploying.
- **NFS permissions:** uid mapping solved in A2 before any code is trusted.
- **Rollback:** gen rollback + `services.immich.enable = true` restore;
  photos untouched by construction; DB restorable from pre-cutover dump if
  v3 migrations are incompatible.

## Definition of Done

- Immich v3.1.0 served on :2283 via quadlet, Caddy routes untouched
- login + browse + upload verified with evidence in `docs/immich-loop/evidence/`
- nightly pg_dump + restic + freshness checks green for 7 days
- module removed, `permittedInsecurePackages` entry dropped, docs updated
- board archived

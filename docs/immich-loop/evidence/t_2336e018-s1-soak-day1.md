# S1 day-1 soak verification — t_2336e018 (2026-09-06)

Read-only drift check vs the C1 baseline (t_9d567a79, gate 11:01 EDT / 15:01Z).
Run from the bees checkout (`~/Code/cn`, loop/wip @ 829ac14), as root, loading
the `loop-verify` API key C1 left at `/tmp/c1-loop-verify-token` (root 0600).

Staged wrapper used (bees:/tmp/s1-soak-verify.sh, kept for later soak days;
note /tmp does not survive reboot — recreate from here if needed):

```bash
#!/usr/bin/env bash
set -uo pipefail
cd /home/crussell/Code/cn || exit 2
sudo -n bash -c 'export IMMICH_API_KEY="$(cat /tmp/c1-loop-verify-token)"; \
  bash scripts/verify-immich.sh --mode soak'
echo "EXIT=$?"
```

(bee-side note: the first attempt ran `sudo -E bash scripts/verify-immich.sh`
directly over ssh — env vars don't cross `sudo -E` from a non-root ssh
session here, so auth rows SKIPped and drift false-FAILed on assets=-1.
The wrapper is the correct pattern; NOT prod drift.)

## Verify run — `--mode soak` @ 2026-09-06 ~15:12Z (11:12 EDT)

```
  PASS units    server: immich-server.service active
  PASS units    ml: immich-machine-learning.service active
  PASS image    immich-server running ghcr.io/immich-app/immich-server:v3.1.0 (running)
  PASS ping     GET /server/ping -> {"res":"pong"}
  PASS version  server reports v3.1.0
  PASS auth     api key accepted (chaddouglasrussell@gmail.com)
  PASS albums   GET /albums -> 1 albums
  PASS assets   library has 4725 assets (floor 1000)
  PASS db       databases: immich postgres
  PASS db       role immich exists
  PASS db       pg extensions present: cube earthdistance pg_trgm plpgsql unaccent uuid-ossp vchord vector
  PASS drift    assets 4725 -> 4725 (baseline ±5% ok; albums 1 -> 1)
  PASS ml       smart search (CLIP via ML) responded — page total=1

Summary: 13 pass, 0 fail, 0 skip
RESULT: PASS    EXIT=0
```

Runbook rows vs C1 baseline — all green (row 8 upload smoke is intentionally
out of scope in soak mode; read-only mandate — C1's gate run covered it):
1 units ✓ 2 image ✓ 3 ping ✓ 4 version ✓ 5 auth ✓ 6 albums+assets ✓
7 db×3 ✓ 9 ml ✓ 10 drift ✓ (baseline recorded 15:01Z: albums=1 assets=4725).

## Drift detail (vs C1 evidence capture, same day ~11:01 EDT)

| Signal | C1 (11:01) | Day-1 (11:13) | Drift |
|---|---|---|---|
| immich-server ActiveEnter | 10:49:08 EDT | 10:49:08 EDT (NRestarts=0) | none |
| immich-ml ActiveEnter | 11:00:40 EDT | 11:00:40 EDT (NRestarts=0) | none |
| Ports | *:2283, 127.0.0.1:3003 | *:2283, 127.0.0.1:3003 | none |
| Images | v3.1.0 / v3.1.0 | v3.1.0 / v3.1.0 | none |
| Albums / assets | 1 / 4725 | 1 / 4725 | none |

Supporting units: postgresql active since 10:39:44 (cutover deploy, NRestarts=0),
redis-immich since 00:53:42 (pre-cutover, untouched, NRestarts=0),
immich-db-dump.timer active/waiting. External ingress
`https://photos.crussell.io/api/server/ping` → `{"res":"pong"}`.

## Journal since cutover gate (11:01 EDT → run time)

- immich-server: **no entries at all** — completely quiet.
- immich-machine-learning: 13 lines total; the only WARNING is the 11:05:53
  `Worker (pid:66) was sent SIGINT!` — immich-ml's built-in 300s inactivity
  recycle ("Shutting down due to inactivity" → boots worker pid:200 →
  "Application startup complete" 1s later). Normal gunicorn worker swap,
  not a restart (unit NRestarts=0, container Up continuously).
- No errors/fatals/exits/kills in either unit since the gate. (The
  asset_exif FK error in the C1 capture predates the gate — transient race
  from the upload smoke deleting its test asset; not re-observed.)

## Verdict

Day-1: GREEN, zero drift, no action. Soak continues (H2 ≥7 days).

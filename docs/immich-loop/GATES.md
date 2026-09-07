# GATES.md — human-gate status for immich-loop
# Operator (Glen/Chad) maintains this file. Workers read it. Append-only log below.

## Current gate status

| Gate | Status | Resolved at |
|---|---|---|
| H1 cutover window (Chad says go) | **granted 2026-09-06; EXECUTED 2026-09-06 15:00Z (verify 18/18 PASS, EXIT=0)** | Chad, #infra thread: "I'm ready for the run book cutover"; C1 evidence: `evidence/cutover/SUMMARY.md` |
| H2 post-soak cleanup (Chad approves) | pending (soak started 2026-09-06T15:00Z, baseline albums=1 assets=4725) | — |

## Log (append only)

- 2026-09-06 — board created; gates H1/H2 pending.
- 2026-09-06 (later) — H1 pending → granted (Chad, #infra): dry-run evidence reviewed, go for cutover. Cutover card C1 queued; loop executes as operator proxy per CONTRACT D6-amended.
- 2026-09-06 (later) — CONTRACT D6 amended: cutover execution delegated to the loop as operator proxy (Chad's chat grant in this thread is the authority; GATES.md + card record it). NixOS deploys to hosts OTHER than bees remain operator-only.
- 2026-09-06 15:00Z — H1 EXECUTED by C1 (operator proxy): cutover commit 68e9272, fixes 829ac14; verify-immich.sh --mode upload --record = 18/18 PASS EXIT=0; baseline albums=1 assets=4725. Two operator deviations (pre-existing postgres-owned DB objects fixed via ALTER OWNER; ML HOME=/cache) — details in evidence/cutover/SUMMARY.md. Soak started; H2 pending.

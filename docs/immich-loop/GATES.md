# GATES.md — human-gate status for immich-loop
# Operator (Glen/Chad) maintains this file. Workers read it. Append-only log below.

## Current gate status

| Gate | Status | Resolved at |
|---|---|---|
| H1 cutover window (Chad says go) | **granted 2026-09-06** | Chad, #infra thread: "I'm ready for the run book cutover" |
| H2 post-soak cleanup (Chad approves) | pending | — |

## Log (append only)

- 2026-09-06 — board created; gates H1/H2 pending.
- 2026-09-06 (later) — H1 pending → granted (Chad, #infra): dry-run evidence reviewed, go for cutover. Cutover card C1 queued; loop executes as operator proxy per CONTRACT D6-amended.
- 2026-09-06 (later) — CONTRACT D6 amended: cutover execution delegated to the loop as operator proxy (Chad's chat grant in this thread is the authority; GATES.md + card record it). NixOS deploys to hosts OTHER than bees remain operator-only.

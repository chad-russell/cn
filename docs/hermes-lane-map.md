# Hermes Lane Map — bee (canonical)

**Where everything lives for the two-agent (Glen ↔ Gloo) setup. One doc, one
home. If it's not listed here, it's not part of the topology.**

- Owner: Glen (default profile). Gloo edits allowed but Glen maintains.
- Verified basis: adversarial topology review 2026-09-05 + live probes.
- Containment rule: memories in Hermes profile homes · life events in
  `~/brain` · infra docs in this repo (this file) · work code in `~/Gloo` ·
  private code outside `~/Gloo` and `~/Code/cn`.

## Naming principle

Personal side = GENERIC names. Work side = GLOO-SPECIFIC names. Display-tier
renames allowed freely; structural renames need strong justification.

## The two agents

| | Glen (personal) | Gloo (work) |
|---|---|---|
| Unit | `hermes-agent.service` | `hermes-gloo-gateway.service` |
| Profile / HERMES_HOME | default: `/var/lib/hermes/.hermes` | `/var/lib/hermes/.hermes/profiles/gloo` |
| Discord bot (app id) | hermes-glen (`1545187919961129123`), nick **Glen** — app still named `hermes-private` (portal rename pending) | hermes-gloo (`1544082952290566235`), nick **Gloo** — app still named `hermes` (portal rename pending) |
| Discord lanes | Personal category (1545197493346766968): #general, #infra, #rmt, #trading, #fantasy-football, #bible-reading, #business-time, #laura, #nsfw, #inbox, #hermes-loop | Gloo category (1544084775499735070): #gloo-general (1544085937577918535) |
| Long-term memory | mem0 → qdrant `mem0` (user `chad`) | mem0 → qdrant `mem0-gloo` (user `chad-gloo`) |
| MCP servers | github | github, linear, vercel |
| Agenix env | `hermes-bee-env-glen.age` | `hermes-gloo-env.age` |
| Nix owner | `hosts/bee/configuration.nix` (upstream module) | `hosts/bee/hermes-gloo.nix` (declarative glooSettings + deep-merge) |
| Model default | glm-5.3 @ zai-coding | glm-5.3 @ zai-coding (gloo provider available for work) |

Shared CORE facts sync between the two `USER.md` files via the
`sync-core-memory` skill (identical copy in both profiles). Everything else —
sessions, mem0, skills — stays isolated. Discord blindness is enforced by
category permission overwrites (403 matrix verified 2026-09-05).

## Supporting cast

| Thing | Where | Notes |
|---|---|---|
| hermes-serve | `10.10.0.12:9119` (Nebula) | Desktop remote surface, glen brain only |
| htb-1 / htb-2 | `profiles/htb-{1,2}` | Kanban workers, no mem0, frozen skill clones |
| Kanban board | default root `kanban/` | Shared across profiles |
| ~/brain | `/home/crussell/brain` | Life events (append-only JSONL) + inbox drops + todo — #inbox doctrine |
| Restic | daily NAS + S3 | `/home/crussell/Gloo`, `/var/lib/hermes`, `/home/crussell/brain` (deployed staticPaths = ground truth) |

## Known quirks

- `hermes profile list` shows gloo as "stopped" — cosmetic; it only knows its
  own supervisor registry, not our systemd units.
- Config deep-merge: Nix owns listed keys; runtime `hermes config set` keys
  survive activations. Stale keys are pruned by the
  `hermes-prune-stale-config` activation script (see configuration.nix).
- Gloo gateway restarts on config drift via the `HERMES_GLOO_DECLARED_CONFIG`
  env-hash; glen's upstream unit is generation-stable — bounce explicitly
  after config changes.
- mem0 collections are created lazily; both `mem0` and `mem0-gloo` verified
  initialized (2026-09-05).

## Pending / decisions open

- Tier B renames — USERNAMES done via Discord API 2026-09-05 (no portal
  needed): personal bot `hermes-private` → **hermes-glen**, work bot
  `bot1544082952290566235` → **hermes-gloo**. (`hermes` as a username is
  globally taken on Discord — hence hermes-glen; symmetric naming,
  Chad-approved.) Remaining (portal-only, ~1 min): APPLICATION display
  names — app `hermes-private` → `hermes-glen`, app `hermes` →
  `hermes-gloo`. A bot token cannot rename its application via API
  (PATCH returns 200 but silently ignores it). Reminder cron 7cfba5f4ee88
  fires 2026-09-06 10:00.
- Home channels declared 2026-09-05 (commit ea47ff0): glen → Personal
  #general (1544084776363888723), gloo → #gloo-general. Stops the
  "No home channel" nag; bare-platform cron deliveries (e.g.
  daily-hermes-state-backup `deliver: discord`) resolve there.
  NOTE: the loader accepts `gateway.platforms.discord.home_channel`
  (nested) as well as top-level `platforms.*`; glen unit is
  generation-stable — bounce after config changes.
- DONE 2026-09-05: channel renamed `general` → `gloo-general` (owner click);
  bot nicknames Glen/Gloo set.
- DECIDED 2026-09-05 (Chad): employer data on personal NAS/S3 restic is
  ACCEPTABLE — everything stays on the one personal backup system.
- DECIDED 2026-09-05 (Chad, ratified): glen contains private lanes —
  "glen = everything personal incl. private, gloo = work only" is standing
  doctrine. The 2026-09-03 strict-separation doctrine is superseded.

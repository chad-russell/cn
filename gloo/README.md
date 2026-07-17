# Gloo dev workflow (local, thinkpad)

Run Gloo projects locally on the thinkpad in **podman-compose dev stacks**,
using the repo-supplied devcontainers plus a small personal override.

This is the personal, thinkpad-local counterpart to the bee dev setup. It
favors **local containers** over SSHing to bee, while reusing the same
devcontainers the whole team uses.

## Architecture

```
~/Gloo/360-polymer/                 cloned repo (code + gitignored .env.local)
~/Code/cn/gloo/                     THIS — orchestration (tracked)
├── overrides/
│   └── polymer.yml                 personal port publish + dev-server command
├── dev                             project/command dispatcher
└── README.md
```

`.env.local` lives in the repo, gitignored (confirmed in polymer's
`.gitignore`), so it's read exactly where the app reads it — no sidecar-repo
split-brain.

## Daily workflow

```bash
# first time (fresh clone): install deps + set up the DB
~/Code/cn/gloo/dev polymer setup

# bring the stack up — db, minio, app(running pnpm dev)
~/Code/cn/gloo/dev polymer up

# the dev server is already running as the app container's PID 1.
# reach it at http://localhost:3000 (polymer) and :3001 (admin360)

# tail dev output / tear down
~/Code/cn/gloo/dev polymer logs
~/Code/cn/gloo/dev polymer down
```

Other commands: `infra` (db+minio only), `migrate`, `seed`. Run `dev polymer`
with no args for the full list.

## Why compose (not raw pods) for now

Each compose service gets DNS on a shared network → the app reaches
`polymer_db:5432` exactly as the repo's env expects. A raw `podman pod` shares
`localhost` but has **no service DNS**, which would force overriding the repo's
env — the exact friction this design avoids. We can graduate to
`podman kube play` / Podman Desktop pods in a later pass; the compose files
translate cleanly.

## Notes

- **bee stays the reference** for `.env.local` and as a remote dev option; this
  setup runs locally.
- **The override is personal** (`userns_mode`, published ports) — never commit
  it to a product repo; `userns_mode` breaks Docker Desktop on macOS.
- **Other projects** (hb, gpl): same pattern — add an override + a case block in
  `dev` once polymer is proven.

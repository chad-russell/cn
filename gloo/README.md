# Gloo dev workflow (local, thinkpad)

Run Gloo projects locally on the thinkpad in **podman-compose dev stacks**,
with **pi running in a per-project `agent` container** that can edit the repo
and drive the sibling containers (db, minio, app).

This is the personal, thinkpad-local counterpart to the bee dev setup. It
favors **local containers** over SSHing to bee, while reusing the same
repo-supplied devcontainers the whole team uses.

## Architecture

```
~/Gloo/360-polymer/                 cloned repo (code + gitignored .env.local)
~/Code/cn/gloo/                     THIS — orchestration + agent context (tracked)
├── overrides/
│   └── polymer.yml                 port publish + agent service (personal)
├── fetch-env.sh                    sync .env.local from bee → local clone
├── setup.sh                        enable podman socket + link skill
└── README.md
```

Two ideas make this clean:

1. **`.env.local` lives in the repo, gitignored** (confirmed in polymer's
   `.gitignore`). So when pi edits env, it edits it where the app reads it —
   no sidecar-repo split-brain. `fetch-env.sh` seeds it from bee once.
2. **pi runs in an `agent` container** (Option A), a peer of the app/db/minio
   containers on the compose network. It mounts the repo (`/workspace`) and the
   host's **rootless podman socket**, so it can `podman exec` into the app
   container to run commands and `podman logs` to read logs — autonomously.

## First-time setup

```bash
# 1. enable the podman socket + link the skill into ~/.pi
~/Code/cn/gloo/setup.sh

# 2. rebuild the dev-shell image so the agent container has `podman`
#    (this adds the podman client to the image pi/the agent uses)
cd ~/Code/cn/atomic/thinkpad/toolbox && ./build.sh
#    then recreate the dev toolbox if you want podman there too:
#    ./create.sh

# 3. fetch polymer's .env.local from bee
~/Code/cn/gloo/fetch-env.sh polymer
```

## Daily workflow

```bash
# first time (fresh clone): install deps + set up the DB
~/Code/cn/gloo/dev polymer setup

# bring the stack up — db, minio, workspace(running pnpm dev), agent
~/Code/cn/gloo/dev polymer up

# the dev server is already running as the app container's PID 1.
# reach it at http://localhost:3000 (polymer) and :3001 (admin360)

# launch pi inside the agent
~/Code/cn/gloo/dev polymer pi

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
- **The override is personal** (`userns_mode`, the `agent` service) — never
  commit it to a product repo; it breaks Docker Desktop on macOS.
- **Other projects** (hb, gpl): same pattern — add an `agent` service to their
  override once polymer is proven.

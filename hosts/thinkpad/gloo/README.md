# Gloo dev workflow (local, thinkpad)

Run Gloo projects locally on the thinkpad in **podman-compose dev stacks**,
using the repo-supplied devcontainers plus a small personal override.

This is the personal, thinkpad-local counterpart to the **bee remote dev
stacks** (`hosts/bee/dev-quadlets/`). It favors **local containers** over
SSHing to bee, while reusing the same devcontainers the whole team uses.

## Architecture

```
~/Gloo/360-polymer/                 cloned repo (code + gitignored .env.local)
~/Code/cn/hosts/thinkpad/gloo/                     THIS — orchestration (tracked)
├── overrides/
│   └── polymer.yml                 personal port publish + dev-server command
└── README.md
```

`.env.local` lives in the repo, gitignored (confirmed in polymer's
`.gitignore`), so it's read exactly where the app reads it — no sidecar-repo
split-brain.

## Why compose (not raw pods) for now

Each compose service gets DNS on a shared network → the app reaches
`polymer_db:5432` exactly as the repo's env expects. A raw `podman pod` shares
`localhost` but has **no service DNS**, which would force overriding the repo's
env — the exact friction this design avoids. We can graduate to
`podman kube play` / Podman Desktop pods in a later pass; the compose files
translate cleanly.

## Notes

- **bee is the remote dev host** — the same gpl/polymer stacks (plus buildspace)
  run there as rootless user-quadlets via `hosts/bee/dev-quadlets.nix`, fronted
  by the bees internal Caddy. See `hosts/bee/dev-quadlets/README.md`.
- **The override is personal** (`userns_mode`, published ports) — never commit
  it to a product repo; `userns_mode` breaks Docker Desktop on macOS.
- **Other projects** (hb, gpl): same pattern

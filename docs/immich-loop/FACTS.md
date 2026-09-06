# Runtime facts (operator-verified 2026-09-06) — read before working

Live bees state, verified over SSH by the operator. This file beats any doc.
Verify anything that smells stale; block if it changed materially.

## Immich today (NixOS module)

- Config: `hosts/bees/immich.nix` — `services.immich.enable`, host 0.0.0.0, port 2283,
  `mediaLocation = /mnt/photos`, `machine-learning.enable = true`.
  `hosts/bees/immich-backup.nix` = nightly pg_dump → `/mnt/photos/backups/` (keep 14).
  Version 2.7.5 (insecure-permitted in nixpkgs 26.05).
- `users.groups.nas-photos = { gid = 1000; }`; immich user extraGroups users(100), nas-photos(1000).
- **Live ids: `immich` uid=991 gid=993, groups 993(immich),100(users),1000(nas-photos).**
- systemd: `immich-server.service` (:2283), `immich-machine-learning.service`, `redis-immich.service`.
- onFailure → ntfy-failure@immich-server.

## Postgres (native, bees)

- PG 17.11 (nixpkgs 26.05 default = postgresql_17; module-sourced config).
- Databases: postgres, template0/1, **immich**.
- pg_hba: local socket = peer; **127.0.0.1/32 and ::1/128 = md5** (TCP needs a password).
- Manage via `sudo -n -u postgres psql ...` over ssh from bee (verified working, NOPASSWD).

## Redis

- `redis-immich.service` (NixOS `services.redis.servers.immich`), logLevel warning.
- Container must reach it on 127.0.0.1 → use host network OR `network host` per quadlet.

## Access from bee (worker environment)

- `ssh -o IdentitiesOnly=yes crussell@10.10.0.6` works BatchMode (key-based). sudo -n verified.
- podman on bees: rootless (crussell) + system quadlets in `/etc/containers/systemd/`.

## Ingress

- Public: gateway Caddy `photos.crussell.io` → `10.10.0.6:2283` (unchanged by this project).
- bees firewall already allows 2283.

## Dry-run sandbox (per CONTRACT)

- `/mnt/photos/.loop-sandbox/` (create; delete when done). Ports 3283 (server) / 3303 (ML).
- Scratch DB name: `immich_dryrun` (create/drop allowed; NOTHING else in PG).

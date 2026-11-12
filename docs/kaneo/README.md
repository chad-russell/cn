# Kaneo (kaneo.crussell.io) — Runbook

Kaneo is the open-source project management tool ([usekaneo/kaneo](https://github.com/usekaneo/kaneo))
replacing the retired Kan/Trello-clone experiments. This is the operator
runbook for the bees deployment.

## Overview

- **URL:** <https://kaneo.crussell.io> — public, terminated by the
  gateway's Caddy (HTTP-01 TLS) and reverse-proxied over Nebula to bees.
  Public DNS comes free from the existing `*.crussell.io` wildcard.
- **No basic_auth** on the Caddy route: Kaneo's own login is the gate.
- Upstream docs: <https://kaneo.app/docs> (install, env vars, upgrades,
  backups, troubleshooting).

## Stack

| Piece | Unit | Detail |
| --- | --- | --- |
| App (web + API) | `kaneo.service` | quadlet, `ghcr.io/usekaneo/kaneo:2.49.0`, publishes `5173:5173` (all interfaces — house pattern so gateway Caddy can reach it over Nebula) |
| Database | `kaneo-postgres.service` | quadlet, `docker.io/library/postgres:16-alpine`, named volume `kaneo_postgres_data`, `pg_isready` healthcheck + `Notify=healthy`, **no published port** |
| Network | `kaneo.network` | bridge; container DNS names `kaneo`, `kaneo-postgres` |

Source files: `hosts/bees/kaneo.nix` (installs the quadlets + owns the
dump/freshness blocks), `hosts/bees/kaneo.container`,
`hosts/bees/kaneo-postgres.container`, `hosts/bees/kaneo.network`,
gateway route in `hosts/gateway/caddy.nix`.

The app unit is `Requires=`/`After=` `kaneo-postgres.service`, which is
`Notify=healthy`, so first-boot DB migrations never race a booting
database.

`kaneo.service` runs its DB migrations itself on start; there is no
separate migrate unit (unlike the old Kan stack).

### State on disk

- `/var/lib/containers/storage/volumes/kaneo_postgres_data/_data` — the
  Postgres data dir (named podman volume, restic-covered via the
  `/var/lib/containers/storage/volumes` backup path).
- `/var/lib/kaneo/db-dumps/` — nightly logical dumps (restic-covered).
  `/var/lib/kaneo` is otherwise just dumps + any future local config.

## Secrets

`secrets/kaneo-env.age` → `/run/agenix/kaneo-env` on bees, consumed by
both containers via `EnvironmentFile=`:

```text
POSTGRES_PASSWORD=<openssl rand -hex 32>
AUTH_SECRET=<openssl rand -hex 32>
```

- `AUTH_SECRET` must be ≥ 32 chars; changing it signs everyone out.
- `POSTGRES_PASSWORD` only takes effect on the **first** init of the
  `kaneo_postgres_data` volume — a later changed value will not match
  the database. Generate fresh values only for a new install.
- Non-secret env lives in `kaneo.container` (`KANEO_CLIENT_URL`,
  `POSTGRES_HOST/DB/USER`, `TRUSTED_PROXIES`, `TZ`; `KANEO_API_URL` is
  deliberately unset — the bundled image derives it from the client URL).

> ⚠️ The committed `kaneo-env.age` is a **single-line placeholder** so
> the flake evaluates. **Before merging/deploying**, replace it with a
> real encrypted file (agenix cannot decrypt the plaintext placeholder,
> so remove it first — `-e` then creates it fresh):
>
> ```bash
> rm secrets/kaneo-env.age
> agenix -e secrets/kaneo-env.age   # paste the two lines above, save
> ```

## First boot checklist

1. Replace the `secrets/kaneo-env.age` placeholder for real — `rm` it,
   then `agenix -e secrets/kaneo-env.age` (see above).
2. Deploy both hosts: `~/Code/cn/scripts/deploy.sh gateway bees`
   (gateway gets the route, bees gets the quadlets).
3. From bees, confirm the API is up:
   ```bash
   curl http://10.10.0.6:5173/api/health
   systemctl status kaneo kaneo-postgres
   ```
4. Visit <https://kaneo.crussell.io> and create the first account —
   that account is the instance admin. (First-boot registration is
   open because `DISABLE_REGISTRATION` is deliberately unset.)
5. **Close registration** — in the admin UI instance settings, or as a
   follow-up env change (`Environment=DISABLE_REGISTRATION=true` in
   `kaneo.container` + redeploy + `systemctl restart kaneo`).
6. Next night, check the dump + freshness check:
   ```bash
   ls -lt /var/lib/kaneo/db-dumps/ | head
   systemctl list-timers kaneo-db-dump
   ```

## Backups

- **Nightly logical dump:** `kaneo-db-dump.service` / `.timer`
  (`OnCalendar=daily`, `Persistent=true`, `RandomizedDelaySec=1h`) runs
  `podman exec kaneo-postgres pg_dump -U kaneo kaneo | gzip` into
  `/var/lib/kaneo/db-dumps/kaneo-pgdump-*.sql.gz`, keeping the newest
  14. Failures alert via `ntfy-failure@kaneo-db-dump.service`.
- **Freshness check:** `homelab.freshnessChecks.kaneo-db` alerts on
  ntfy if the newest dump is older than 36 h (or missing).
- **Restic:** `/var/lib/kaneo` is in the bees backup paths
  (`hosts/bees/backup.nix`); the postgres volume itself is covered by
  the `/var/lib/containers/storage/volumes` path.
- Restore sketch (fresh bees): bring the quadlets up with an empty
  volume, `gunzip -c kaneo-pgdump-<ts>.sql.gz | podman exec -i
  kaneo-postgres psql -U kaneo -d kaneo`, then restart `kaneo.service`.

## Upgrades

The image is **version-pinned** (`ghcr.io/usekaneo/kaneo:2.49.0`) and
has no `AutoUpdate=registry` label, so the nightly podman auto-update
(`hosts/bees/podman-auto-update.nix`) never touches this stack.

To upgrade: check the [upstream release notes](https://github.com/usekaneo/kaneo/releases)
and [upgrade guide](https://kaneo.app/docs/core/operations/upgrades),
bump the tag in `hosts/bees/kaneo.container`, deploy bees, then
`systemctl restart kaneo` (migrations run on start). Postgres stays on
16-alpine unless upstream says otherwise
([16→18 guide](https://kaneo.app/docs/core/operations/postgresql-18)).

## Troubleshooting

```bash
# on bees
systemctl status kaneo kaneo-postgres
journalctl -u kaneo -f            # app + API logs
journalctl -u kaneo-postgres -f
podman logs kaneo --tail=100
podman logs kaneo-postgres --tail=100
curl http://10.10.0.6:5173/api/health   # expect 200
podman exec kaneo-postgres pg_isready -U kaneo -d kaneo
podman volume inspect kaneo_postgres_data

# on gateway (502/504 → backend unreachable over Nebula)
journalctl -u caddy -f
curl -s http://10.10.0.6:5173/api/health  # from gateway, same path Caddy uses
```

Common cases:

- **502 at the URL but health OK from bees** → gateway can't reach
  `10.10.0.6:5173` (Nebula down, or the all-interfaces `PublishPort=`
  was changed to a loopback bind).
- **App crash-loops with an AUTH/DB error** → `/run/agenix/kaneo-env`
  is still the placeholder, or `POSTGRES_PASSWORD` was rotated after
  the volume's first init (only valid pre-first-init).
- **Migrations failed on first boot** → `journalctl -u kaneo-postgres`;
  once the DB is healthy, `systemctl restart kaneo` retries them.
- **Dump timer never fires** → `systemctl list-timers kaneo-db-dump`;
  failures land on the homelab-alerts ntfy topic.

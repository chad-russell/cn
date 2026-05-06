# Gloo Containerized Dev Stack Design

## Goal

Move Gloo on `bee` from native NixOS user services to a containerized dev workflow that is:

- reliable on NixOS
- easy for humans to operate
- easy for LLMs to fully manage
- compatible with live reload
- able to selectively run subsets of the stack
- non-invasive to the source repos whenever possible

---

## Core Decision

Use:

- **one shared `Containerfile`**
- **one compose project**
- **one container per app service**
- **shared infra containers**
- **one toolbox container** for ad-hoc operations

Do **not** use one giant app container running everything via `concurrently`.

### Why

This better matches real workflows:

- `hb-web` + `hb-api` when working on Hummingbird
- `gpl` + `hb-api` when working on GPL
- `polymer` standalone when working on Polymer
- all app services share postgres/rustfs infra

It is also much easier for an LLM to:

- start specific services
- stop specific services
- tail logs for one service
- restart one broken thing without touching the others
- run migrations/seeds from a toolbox container

---

## Service Layout

### Shared infra

- `postgres`
- `rustfs`
- `pgadmin`

### App services

- `hb-api`
- `hb-web`
- `gpl`
- `polymer`
- `storyhub`
- `storyhub-worker`

### Admin / bootstrap

- `toolbox`
- `hummingbird-bootstrap`
- `gpl-bootstrap`
- `polymer-bootstrap`

---

## Dependency Graph

### Infra dependencies

All app services depend on:

- `postgres`
- `rustfs`

### App-level dependencies

- `hb-web` depends on `hb-api`
- `gpl` depends on `hb-api`
- `polymer` is standalone
- `storyhub` and `storyhub-worker` share the Hummingbird repo and shared infra

### Operational groups / work modes

#### Hummingbird

- `postgres`
- `rustfs`
- `pgadmin`
- `hummingbird-bootstrap`
- `hb-api`
- `hb-web`

#### GPL

- `postgres`
- `rustfs`
- `pgadmin`
- `hummingbird-bootstrap`
- `gpl-bootstrap`
- `hb-api`
- `gpl`

#### Polymer

- `postgres`
- `rustfs`
- `pgadmin`
- `polymer-bootstrap`
- `polymer`

#### Storyhub

- `postgres`
- `rustfs`
- `pgadmin`
- `hummingbird-bootstrap`
- `storyhub`
- `storyhub-worker`

---

## Networking Model

### Recommendation

Use a **normal compose bridge network**.

Reasons:

- clean service discovery (`postgres`, `rustfs`, `hb-api`)
- standard compose behavior
- better isolation
- easier inspection/debugging

### Published ports

Expose the ports needed for Caddy and direct access on `bee`:

- `hb-api` -> `8000`
- `hb-web` -> `3100`
- `gpl` -> `3106`
- `polymer` -> `3001`
- `storyhub` -> `3007`
- `storyhub-worker` -> optional `8001`
- `pgadmin` -> `5050`
- `rustfs` -> `9000`
- `rustfs-console` -> `9001`
- `postgres` -> `5433`

### In-network service addresses

Inside compose, services should talk to:

- `postgres:5432`
- `rustfs:9000`
- `hb-api:8000`

Container env files should be adjusted accordingly rather than relying on host localhost mappings.

---

## Volume Strategy

### Source code

Bind mount:

- `/home/crussell/Gloo:/work`

### Keep mutable/generated files out of the repo when possible

Use named volumes for things like:

- `360-gpl/node_modules`
- `360-gpl/.next`
- `360-hummingbird/node_modules`
- `360-hummingbird/api/generated`
- `360-hummingbird/storyhub/generated`
- `360-hummingbird/storyhub/.next`
- `360-polymer/node_modules`
- `360-polymer/apps/polymer/.next`
- optional turborepo caches
- shared `pnpm-store`

### Container user

Run app containers as:

- `user: "1000:100"`

This helps avoid ownership problems if anything writes into the bind-mounted repo.

---

## Environment Strategy

### Rule

Do **not** modify project source repos unless absolutely necessary.

### Existing env files

Keep current host-managed envs:

- `/etc/gloo/envs/*.env`

### Add container-specific env files

Create Nix-managed container env files such as:

- `hb-api.container.env`
- `hb-web.container.env`
- `gpl.container.env`
- `polymer.container.env`
- `storyhub.container.env`
- `storyhub-worker.container.env`

These may differ from host-native envs by using service names like:

- DB host -> `postgres`
- RustFS/S3 host -> `rustfs`
- internal API host -> `hb-api`

Also load:

- `/run/agenix/gloo-secrets`

---

## Shared Image Design

### One `Containerfile`

Use a shared image containing:

- Node 24
- pnpm
- bun
- common Linux deps needed by Next/Prisma/native modules
- optionally `postgresql-client`, `git`, `curl`, `jq`

All app, bootstrap, and toolbox services should use the same image.

### Important

Do **not** use one giant app container with `concurrently`.

Each app service should run one command in one container.

---

## Compose Model

### App services

Each app service should define:

- shared image
- working directory
- env files
- source bind mount
- named volumes
- command
- published ports
- `depends_on` for infra and, where appropriate, `hb-api`

### Bootstrap services

One-shot services that run and exit:

#### `hummingbird-bootstrap`

- `pnpm install`
- prisma generate for api
- prisma generate for storyhub-prisma

#### `gpl-bootstrap`

- `pnpm install`

#### `polymer-bootstrap`

- `pnpm install`

### Toolbox

A reusable service for:

- migrations
- seeds
- prisma generate
- `pnpm install`
- DB inspection
- shell access

Use it via:

- `podman compose run --rm toolbox bash`

---

## Systemd Model

### Per-service user units

Create user units such as:

- `gloo-postgres.service`
- `gloo-rustfs.service`
- `gloo-pgadmin.service`
- `gloo-hb-api.service`
- `gloo-hb-web.service`
- `gloo-gpl.service`
- `gloo-polymer.service`
- `gloo-storyhub.service`
- `gloo-storyhub-worker.service`

Each wrapper should map to compose operations for a single service.

### Bootstrap units

- `gloo-bootstrap-hummingbird.service`
- `gloo-bootstrap-gpl.service`
- `gloo-bootstrap-polymer.service`

Each should wrap:

- `podman compose run --rm <bootstrap-service>`

### Convenience targets

- `gloo-infra.target`
- `gloo-hummingbird.target`
- `gloo-gpl.target`
- `gloo-polymer.target`
- `gloo-storyhub.target`
- `gloo-all.target`

### Important operational note

Targets are mainly for **start convenience**.

For stopping, prefer stopping leaf services explicitly because:

- `hb-api` is shared by Hummingbird and GPL

So future LLMs should:

- start with targets
- stop individual services unless intentionally tearing down a whole group

---

## Logging / Operations Model

### Logs

Use compose logs for service-level debugging:

- `podman compose logs -f hb-api`
- `podman compose logs -f polymer`

Use systemd logs mainly for wrapper failures.

### Toolbox

Open shell:

- `podman compose run --rm toolbox bash`

### Migrations / seeds

Run from toolbox, not from host-native processes.

### Live reload

Should happen inside each app container via bind-mounted source.

---

# Execution Task List for Future LLMs

## Phase 0 — Freeze design

1. Treat this file as the architecture source for the Gloo containerization effort.
2. Do not modify project source repos unless absolutely necessary.
3. Prefer repo-local infra/config changes under `hosts/bee/` and related Nix files.

---

## Phase 1 — Scaffold non-destructively

1. Add a new containerized Gloo layout under `hosts/bee/gloo/`
2. Create:
   - shared `Containerfile`
   - compose file
   - bootstrap services
   - toolbox service
   - container-specific env files
3. Add new Nix-managed user units/targets for the containerized stack
4. Keep the current native Gloo setup intact during this phase

### Success criteria

- Nix config evaluates
- bee can build the shared image
- systemd sees the new user units/targets

---

## Phase 2 — Validation namespace / ports

1. Choose a temporary validation port map so containerized Gloo can run alongside native Gloo
2. Prefer alternate high ports during validation
3. Optionally add temporary Caddy routes or temp hostnames for validation

### Success criteria

- containerized services can be exercised without taking down the current setup

---

## Phase 3 — Bootstrap and first start

1. Deploy bee with the new containerized config
2. Start:
   - `gloo-infra.target`
3. Run bootstrap units:
   - `gloo-bootstrap-hummingbird.service`
   - `gloo-bootstrap-gpl.service`
   - `gloo-bootstrap-polymer.service`
4. Start workflow groups one by one:
   - Hummingbird
   - GPL
   - Polymer
   - Storyhub

### Success criteria

- all services start in containers on validation ports

---

## Phase 4 — Workflow validation

### Hummingbird

- start `hb-api` + `hb-web`
- log in
- verify API requests succeed
- verify live reload
- test migrations/seeds from toolbox

### GPL

- start `hb-api` + `gpl`
- log in / verify data
- verify live reload

### Polymer

- start `polymer`
- verify standalone behavior
- verify live reload

### Storyhub

- start `storyhub` + `storyhub-worker`
- validate generated client behavior
- validate filesystem/permission behavior

### Infra

- verify postgres access
- verify pgadmin
- verify rustfs and buckets

---

## Phase 5 — LLM operations validation

Explicitly validate that an LLM can reliably do the following:

1. start Hummingbird
2. stop hb-web only
3. tail hb-api logs
4. open toolbox shell
5. run prisma generate
6. run a migration
7. inspect postgres
8. restart polymer
9. verify live reload after a code edit

### Success criteria

- operations are predictable and agent-manageable

---

## Phase 6 — Cutover

**Pause for human approval before this phase.**

1. Stop native Gloo services
2. Switch containerized ports/routes to final values
3. Update Caddy to point to the containerized services
4. Reload/restart Caddy
5. Re-test all internal routes

### Success criteria

- containerized Gloo becomes the active dev stack

---

## Phase 7 — Cleanup

1. Remove old native Gloo unit generation from `hosts/bee/gloo.nix`
2. Leave Buildspace untouched unless explicitly migrating it
3. Document:
   - startup commands
   - stop commands
   - toolbox commands
   - migration/seed commands
   - dependency graph

---

# Recommended Command Model for Future LLMs

## Start infra

- `systemctl --user start gloo-infra.target`

## Start a workflow

- `systemctl --user start gloo-hummingbird.target`
- `systemctl --user start gloo-gpl.target`
- `systemctl --user start gloo-polymer.target`
- `systemctl --user start gloo-storyhub.target`

## Stop safely

Prefer stopping leaf services explicitly:

- `systemctl --user stop gloo-hb-web.service`
- `systemctl --user stop gloo-gpl.service`
- `systemctl --user stop gloo-polymer.service`

## Logs

- `podman compose logs -f hb-api`

## Toolbox

- `podman compose run --rm toolbox bash`

---

## Notes

- Current native Gloo setup may remain temporarily during migration.
- Validation should happen on temporary ports or temporary routes before final cutover.
- Avoid changing source repos unless there is no other viable path.

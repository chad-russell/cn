#!/usr/bin/env bash
#
# dev-server.sh — PID 1 of the hummingbird-quadlet app container (bee edition).
#
# On first start it enables pnpm (corepack) if needed, installs deps, installs
# postgresql-client (for the seed script's psql-based dump restore), waits for
# Postgres, generates the Prisma client, then launches the API (Express/tsx
# watch :8000) and web (Vite :3000) dev servers in parallel and blocks until
# either exits — at which point the container stops so you can read the logs
# and restart it manually (systemctl --user restart hummingbird-dev-app).
#
# This file is Nix-managed (materialized under /etc/dev-quadlets/hummingbird/)
# and bind-mounted read-only into the container at /usr/local/bin/dev-server.sh,
# so nothing is vendored into the hummingbird checkout. Hummingbird is reached
# over SSH tunnels (laptop localhost:3000/8000 -> bee:3300/3308; see
# `cjust dev-tunnel` / `cjust dev-up`), so the apps see localhost.
set -u

cd /workspace || { echo "FATAL: /workspace not mounted" >&2; exit 1; }

# The devcontainers/javascript-node image ships pnpm via corepack; enable it if
# `pnpm` isn't already on PATH.
command -v pnpm >/dev/null 2>&1 || corepack enable >/dev/null 2>&1 || true

# Install postgresql-client (needed by the seed script's psql-based dump restore).
# The devcontainers image doesn't include psql. Run this EVERY start (not just
# first start) because container restarts start from the image, not from a
# previous container filesystem — so psql from a prior start is gone.
if ! command -v psql >/dev/null 2>&1; then
  echo "==> installing postgresql-client (for seed psql) ..."
  apt-get update -qq && apt-get install -y -qq postgresql-client >/dev/null 2>&1 || true
fi

if [ ! -d node_modules ]; then
  echo "==> first start: pnpm install"
  # pnpm 11 fails when dependency build scripts aren't on the allowlist. The
  # repo's pnpm-workspace.yaml has allowBuilds for the key deps; this flag is a
  # safety net that runs every dep's build script for THIS command only (no
  # persisted changes). It's a no-op on pnpm versions that don't know the key.
  pnpm install --config.dangerously-allow-all-builds=true \
    || { echo "FATAL: pnpm install failed" >&2; exit 1; }
fi

# Wait for Postgres. The devcontainers base image has no pg_isready; use node's
# net module for a TCP readiness check.
echo "==> waiting for postgres at hummingbird-db:5432 ..."
node <<'NODE' || { echo "FATAL: postgres not reachable" >&2; exit 1; }
const net = require("net");
(function check(attempt) {
  const s = net.createConnection({ host: "hummingbird-db", port: 5432 }, () => {
    s.end();
    console.log("==> postgres is ready");
    process.exit(0);
  });
  s.on("error", () => {
    if (attempt >= 90) {
      console.error("postgres not reachable after ~90s");
      process.exit(1);
    }
    setTimeout(() => check(attempt + 1), 1000);
  });
})(0);
NODE

# Generate Prisma client + Rev79 GraphQL codegen (the API imports both at boot).
echo "==> generating prisma client + rev79 codegen ..."
pnpm --filter api run prisma:generate || true
pnpm --filter api run rev79:codegen || true

# Start the API (Express + tsx watch, binds 0.0.0.0:8000 in dev mode).
# Set PORT=8000 inline so the API uses it — but vite (web) doesn't inherit it
# (vite reads PORT via loadEnv and would collide if it were in the container env).
echo "==> api  -> http://0.0.0.0:8000"
cd /workspace/api && PORT=8000 pnpm run dev &
PID_API=$!

# Start the web (Vite, binds 0.0.0.0:3000; CONTAINER=true enables poll-based
# file watching for reliable HMR over the bind mount). Vite defaults to :3000
# via vite.config.ts (PORT || '3000'), and we don't set PORT in its env.
echo "==> web  -> http://0.0.0.0:3000"
cd /workspace/web && CONTAINER=true NODE_ENV=development APP_ENV=local pnpm run dev &
PID_WEB=$!

# On stop (SIGTERM from podman) / Ctrl-C, tear both dev servers down and exit 0
# so systemd records a clean stop (inactive, not failed) — which is what lets
# the `PartOf=` cascade stop the db. A *natural* crash of a dev server skips
# the trap, so `wait -n` returns non-zero and the container fails loudly instead.
trap 'kill "$PID_API" "$PID_WEB" 2>/dev/null || true; exit 0' TERM INT

# Block until either dev server exits, then let the container stop.
wait -n "$PID_API" "$PID_WEB"

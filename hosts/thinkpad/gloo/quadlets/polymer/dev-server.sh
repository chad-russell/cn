#!/usr/bin/env bash
#
# dev-server.sh — PID 1 of the polymer-quadlet app container.
#
# Mirrors the compose override's `app` command. On first start it installs
# deps, waits for Postgres, then launches both Next.js dev servers in parallel
# and blocks until either exits — at which point the container stops so you can
# see the crash and restart it manually (systemctl --user restart polymer-dev-app).
#
#   apps/polymer   -> :3000   (webpack; --turbo is disabled — it panics on polymer)
#   apps/admin360  -> :3001   (turbo)
#
# This file lives OUTSIDE the product repo (under ~/Code/cn/hosts/thinkpad/gloo/quadlets/polymer)
# and is bind-mounted read-only into the container at /usr/local/bin/dev-server.sh,
# so nothing is vendored into the polymer checkout.
set -u

cd /workspace || { echo "FATAL: /workspace not mounted" >&2; exit 1; }

# The devcontainers/javascript-node image ships pnpm via corepack; enable it if
# `pnpm` isn't already on PATH (the old custom image pre-baked pnpm, this one
# doesn't).
command -v pnpm >/dev/null 2>&1 || corepack enable >/dev/null 2>&1 || true

if [ ! -d node_modules ]; then
  echo "==> first start: pnpm install"
  pnpm install || { echo "FATAL: pnpm install failed" >&2; exit 1; }
fi

# The devcontainers base image has no pg_isready (the old custom image did); use
# node's net module for a TCP readiness check. Postgres accepts connections as
# soon as the socket is open, which is good enough before db:push / the dev server.
echo "==> waiting for postgres at polymer_db:5432 ..."
node <<'NODE' || { echo "FATAL: postgres not reachable" >&2; exit 1; }
const net = require("net");
(function check(attempt) {
  const s = net.createConnection({ host: "polymer_db", port: 5432 }, () => {
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

echo "==> apps/polymer  -> http://0.0.0.0:3000 (webpack, no turbo)"
pnpm --dir apps/polymer exec next dev -H 0.0.0.0 &
PID_POLY=$!

echo "==> apps/admin360 -> http://0.0.0.0:3001 (turbo)"
pnpm --dir apps/admin360 exec next dev --turbo --port 3001 -H 0.0.0.0 &
PID_ADMIN=$!

# On stop (SIGTERM from podman) / Ctrl-C, tear both dev servers down and exit 0
# so systemd records a clean stop (inactive, not failed) — which is what lets the
# `PartOf=` cascade stop db & minio. A *natural* crash of a dev server skips the
# trap, so `wait -n` returns non-zero and the container fails loudly instead.
trap 'kill "$PID_POLY" "$PID_ADMIN" 2>/dev/null || true; exit 0' TERM INT

# Block until either dev server exits, then let the container stop.
wait -n "$PID_POLY" "$PID_ADMIN"

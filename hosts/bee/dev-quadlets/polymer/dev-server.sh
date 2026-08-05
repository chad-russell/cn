#!/usr/bin/env bash
#
# dev-server.sh — PID 1 of the polymer-quadlet app container (bee edition).
#
# Installs deps, waits for Postgres, then launches both Next.js dev servers in
# parallel and blocks until either exits — at which point the container stops so
# you can see the crash and restart it manually (systemctl --user restart polymer-dev-app).
#
#   apps/polymer   -> :3000   (webpack; --turbo is disabled — it panics on polymer)
#   apps/admin360  -> :3001   (turbo)
#
# bee/Caddy difference from the thinkpad version: both apps are fronted by the
# bees Caddy under *.internal.crussell.io. Because the two apps share ONE
# container / process-env but each needs its OWN NEXT_PUBLIC_BASE_URL, those
# public origins are injected INLINE at each `next dev` launch below (a single
# Environment= in the .container can't give each app a different value).
# Next.js will NOT override an already-set process env from .env / .env.local, so
# these inline values win. WORKOS_COOKIE_DOMAIN is exported once (shared) so auth
# cookies are scoped across both *.internal.crussell.io subdomains. You must
# still register the new redirect URIs in the WorkOS dashboard — see README.
#
# This file is Nix-managed (materialized under /etc/dev-quadlets/polymer/) and
# bind-mounted read-only into the container, so nothing is vendored into the
# polymer checkout.
set -u

cd /workspace || { echo "FATAL: /workspace not mounted" >&2; exit 1; }

# Scope WorkOS auth cookies across both polymer/admin360 subdomains so a sign-in
# on one is recognized by the other (matches the production cross-subdomain model
# described in apps/*/.env.example WORKOS_COOKIE_DOMAIN).
export WORKOS_COOKIE_DOMAIN=.internal.crussell.io

# The devcontainers/javascript-node image ships pnpm via corepack; enable it if
# `pnpm` isn't already on PATH.
command -v pnpm >/dev/null 2>&1 || corepack enable >/dev/null 2>&1 || true

if [ ! -d node_modules ]; then
  echo "==> first start: pnpm install"
  pnpm install || { echo "FATAL: pnpm install failed" >&2; exit 1; }
fi

# The devcontainers base image has no pg_isready; use node's net module for a TCP
# readiness check. Postgres accepts connections as soon as the socket is open,
# which is good enough before db:push / the dev server.
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

# Per-app public origins (Caddy). Inline env on the `next dev` invocation is the
# only way to give each app a distinct NEXT_PUBLIC_BASE_URL from one container.
echo "==> apps/polymer  -> http://0.0.0.0:3000 (webpack, no turbo)  [Caddy: https://polymer.internal.crussell.io]"
NEXT_PUBLIC_BASE_URL=https://polymer.internal.crussell.io \
NEXT_PUBLIC_WORKOS_REDIRECT_URI=https://polymer.internal.crussell.io/callback \
NEXT_PUBLIC_ADMIN360_URL=https://admin360.internal.crussell.io \
  pnpm --dir apps/polymer exec next dev -H 0.0.0.0 &
PID_POLY=$!

echo "==> apps/admin360 -> http://0.0.0.0:3001 (turbo)  [Caddy: https://admin360.internal.crussell.io]"
NEXT_PUBLIC_BASE_URL=https://admin360.internal.crussell.io \
NEXT_PUBLIC_WORKOS_REDIRECT_URI=https://admin360.internal.crussell.io/callback \
NEXT_PUBLIC_POLYMER_URL=https://polymer.internal.crussell.io \
  pnpm --dir apps/admin360 exec next dev --turbo --port 3001 -H 0.0.0.0 &
PID_ADMIN=$!

# On stop (SIGTERM from podman) / Ctrl-C, tear both dev servers down and exit 0
# so systemd records a clean stop (inactive, not failed) — which is what lets the
# `PartOf=` cascade stop db & minio. A *natural* crash of a dev server skips the
# trap, so `wait -n` returns non-zero and the container fails loudly instead.
trap 'kill "$PID_POLY" "$PID_ADMIN" 2>/dev/null || true; exit 0' TERM INT

# Block until either dev server exits, then let the container stop.
wait -n "$PID_POLY" "$PID_ADMIN"

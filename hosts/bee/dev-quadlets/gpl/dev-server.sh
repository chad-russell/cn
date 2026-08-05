#!/usr/bin/env bash
#
# dev-server.sh — PID 1 of the gpl-quadlet app container (bee edition).
#
# On first start it enables pnpm (corepack) if needed, installs deps, waits for
# Postgres, ensures the MinIO `gpl-assets` bucket exists (using the repo's own
# @aws-sdk/client-s3 dependency), then launches the Next.js dev server on :3006
# and blocks until it exits — at which point the container stops so you can read
# the logs and restart it manually (systemctl --user restart gpl-dev-app).
#
# bee/Caddy difference from the thinkpad version: the app is fronted by the bees
# Caddy at https://gpl.internal.crussell.io (see hosts/bees/caddy/routes/internal/dev.caddy).
# For auth we FORCE gpl's LOCAL DEV AUTH FALLBACK (no Hummingbird SSO), matching
# the thinkpad dev experience. gpl's src/lib/hummingbird-login.ts selects SSO
# only when BETTER_AUTH_URL is a NON-localhost URL; .env.local sets it to
# localhost:3006 (→ local fallback on the thinkpad). We set BOTH auth URLs to
# EMPTY below so: (a) shouldUseLocalAuthFallback() stays true (no Hummingbird
# redirect, no localhost SSO URL), and (b) Next.js's env loader sees them as
# already-set and does NOT overlay the localhost values from /workspace/.env.local.
# better-auth then derives its URLs from the request host (gpl.internal.crussell.io)
# → correct behind the proxy with zero SSO setup. (To use real Hummingbird SSO
# here instead, set these to https://gpl.internal.crussell.io and register the
# callback URI in the Hummingbird dashboard.)
#
# This file is Nix-managed (materialized under /etc/dev-quadlets/gpl/) and
# bind-mounted read-only into the container, so nothing is vendored into the gpl
# checkout.
set -u

cd /workspace || { echo "FATAL: /workspace not mounted" >&2; exit 1; }

# Force the local dev auth fallback behind Caddy (see header comment). EMPTY, not
# unset — unset would let Next.js overlay the localhost value from .env.local and
# flip gpl into Hummingbird SSO mode (which then redirects to localhost:3000).
export BETTER_AUTH_URL=""
export NEXT_PUBLIC_BETTER_AUTH_URL=""

# The devcontainers/javascript-node image ships pnpm via corepack; enable it if
# `pnpm` isn't already on PATH.
command -v pnpm >/dev/null 2>&1 || corepack enable >/dev/null 2>&1 || true

if [ ! -d node_modules ]; then
  echo "==> first start: pnpm install"
  # pnpm 11 fails `install` (ERR_PNPM_IGNORED_BUILDS) when dependency build scripts
  # aren't on the allowlist. esbuild + @tailwindcss/oxide NEED their builds to run
  # (they fetch/build native binaries the app won't boot without), so we can't use
  # --ignore-scripts. The escape hatch is dangerouslyAllowAllBuilds: passed inline
  # it runs every dep's build script for THIS command only and writes NOTHING to
  # the repo (unlike `pnpm approve-builds`, which persists the list into
  # pnpm-workspace.yaml / package.json — off-limits per our no-repo-mods rule).
  # It's a no-op on pnpm versions that don't know the key, so it's version-safe.
  pnpm install --config.dangerously-allow-all-builds=true \
    || { echo "FATAL: pnpm install failed" >&2; exit 1; }
fi

# The base image has no pg_isready; use node's net module for a TCP readiness
# check. Postgres accepts connections as soon as the socket is open, which is
# good enough before db:push / the dev server.
echo "==> waiting for postgres at gpl-db:5432 ..."
node <<'NODE' || { echo "FATAL: postgres not reachable" >&2; exit 1; }
const net = require("net");
(function check(attempt) {
  const s = net.createConnection({ host: "gpl-db", port: 5432 }, () => {
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

# Ensure the MinIO `gpl-assets` bucket exists (idempotent). @aws-sdk/client-s3 is
# a repo dependency; resolve it via NODE_PATH so no separate mc image is needed.
# Self-diagnosing: it (1) TCP-checks MinIO first so the log distinguishes
# "minio unreachable" from "minio up but create failing", then (2) loops on
# CreateBucket, treating already-exists (BucketAlreadyOwnedByYou / 409) as
# success and LOGGING every error instead of swallowing it.
echo "==> ensuring MinIO bucket gpl-assets ..."
NODE_PATH=/workspace/node_modules node <<'NODE' || { echo "FATAL: MinIO bucket setup failed" >&2; exit 1; }
const { S3Client, CreateBucketCommand } = require("@aws-sdk/client-s3");
const net = require("net");

// Wait for the MinIO API port, distinguishing "unreachable" from "create failing".
function waitForPort(host, port, attempts) {
  return new Promise((resolve) => {
    (function check(n) {
      const s = net.createConnection({ host, port }, () => { s.end(); resolve(true); });
      s.on("error", () => (n <= 0 ? resolve(false) : setTimeout(() => check(n - 1), 1000)));
    })(attempts);
  });
}

const s3 = new S3Client({
  endpoint: "http://gpl-minio:9000",
  region: "us-east-1",
  forcePathStyle: true,
  credentials: { accessKeyId: "minioadmin", secretAccessKey: "minioadmin" },
});
const bucket = "gpl-assets";

(async () => {
  const reachable = await waitForPort("gpl-minio", 9000, 60);
  if (!reachable) {
    console.error("minio API not reachable at gpl-minio:9000 after ~60s");
    process.exit(1);
  }
  console.log("==> minio API reachable");

  let lastErr;
  for (let i = 1; i <= 30; i++) {
    try {
      await s3.send(new CreateBucketCommand({ Bucket: bucket }));
      console.log("==> bucket " + bucket + " created");
      process.exit(0);
    } catch (e) {
      const name = (e && e.name) || "Error";
      const status = (e && e.$metadata && e.$metadata.httpStatusCode) || "-";
      // MinIO returns 409 BucketAlreadyExists; S3 returns BucketAlreadyOwnedByYou.
      if (name === "BucketAlreadyOwnedByYou" || name === "BucketAlreadyExists" || status === 409) {
        console.log("==> bucket " + bucket + " already exists");
        process.exit(0);
      }
      lastErr = e;
      console.error("bucket setup: attempt " + i + "/30: " + name + " (http " + status + "): " + (e && e.message));
    }
    await new Promise((r) => setTimeout(r, 1000));
  }
  console.error("bucket " + bucket + " not ready after 30 attempts; last error:");
  console.error(lastErr ? (lastErr.stack || String(lastErr)) : "(unknown)");
  process.exit(1);
})();
NODE

# Bind to 0.0.0.0 so the published :3006 is reachable from the host (and through
# the bees Caddy). The repo's `dev` script (`next dev -p 3006`) binds to localhost,
# which would be invisible outside the container.
echo "==> gpl -> http://0.0.0.0:3006  (Caddy: https://gpl.internal.crussell.io)"
pnpm exec next dev -p 3006 -H 0.0.0.0 &
PID_APP=$!

# On stop (SIGTERM from podman) / Ctrl-C, tear the dev server down and exit 0 so
# systemd records a clean stop (inactive, not failed) — which is what lets the
# `PartOf=` cascade stop db & minio. A *natural* crash skips the trap, so `wait`
# returns non-zero and the container fails loudly instead.
trap 'kill "$PID_APP" 2>/dev/null || true; exit 0' TERM INT

# Block until the dev server exits, then let the container stop.
wait "$PID_APP"

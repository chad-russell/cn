#!/usr/bin/env bash
#
# dev-server.sh — PID 1 of the buildspace-quadlet app container (bee edition).
#
# On first start it runs `bun install` across the monorepo, waits for Postgres,
# ensures the MinIO `buildspace-internal` bucket exists, then launches the whole
# dev surface via `turbo run dev --env-mode=loose` (all 10 tasks in parallel: 9
# apps/services + packages/db drizzle studio) and blocks until turbo exits. If a
# dev server crashes, turbo stops and the container stops so you can read the
# logs and restart it manually (systemctl --user restart buildspace-dev-app).
#
# NB: turbo is invoked with --env-mode=loose (NOT via the repo's bare `bun dev`
# script) because turbo.json declares `env` on the `build` task, which engages
# turbo's STRICT env mode and would otherwise strip DATABASE_URL / RESEND_API_KEY
# / BUILDSPACE_SUPER_ADMIN_EMAILS from each task (e.g. packages/db's drizzle
# studio and apps/runtime both crash on a missing env at boot). `loose` forwards
# the container's full environment to every task.
#
# Apps started (from apps/*/package.json + services/code-review, via turbo):
#   marketplace :3000 | runtime :3002      | login :3003        | docs :3004
#   studio :3005     | super-admin :3006   | code-review :3007  | registry :3008
#   jobs :3010
#
# bee/Caddy note: buildspace has no known URL/origin env at the compose level
# (apps bind 0.0.0.0 and use relative URLs), so unlike gpl/polymer no per-app
# public-origin env is injected here. If an app generates wrong absolute URLs
# behind the bs-*.internal.crussell.io Caddy names, add the override inline at
# its launch (or via apps/<app>/.env.local) — see the README.
#
# This file is Nix-managed (materialized under /etc/dev-quadlets/buildspace/)
# and bind-mounted read-only into the container at /usr/local/bin/dev-server.sh,
# so nothing is vendored into the buildspace checkout.
set -u

cd /workspace || { echo "FATAL: /workspace not mounted" >&2; exit 1; }

# bun caches into HOME; make sure it exists and is writable (root inside the
# container; /tmp is always writable).
mkdir -p "${HOME:-/tmp/buildspace-home}" "${BUN_INSTALL:-/tmp/buildspace-home/.bun}"

if [ ! -d node_modules ]; then
  echo "==> first start: bun install (this can take a few minutes on a big monorepo)"
  bun install || { echo "FATAL: bun install failed" >&2; exit 1; }
fi

# Wait for Postgres. The oven/bun image is Debian-based and has bash with
# /dev/tcp, so no node/pg_isready needed. Postgres accepts connections as soon as
# the socket is open, which is good enough before db:migrate / the dev servers.
echo "==> waiting for postgres at postgres:5432 ..."
pg_ready=false
for i in $(seq 1 120); do
  if (exec 3<>/dev/tcp/postgres/5432) 2>/dev/null; then
    exec 3>&- 3<&- 2>/dev/null || true
    pg_ready=true
    break
  fi
  sleep 1
done
if [ "$pg_ready" != true ]; then
  echo "FATAL: postgres not reachable at postgres:5432 after ~120s" >&2
  exit 1
fi
echo "==> postgres is ready"

# Ensure the MinIO `buildspace-internal` bucket exists (best-effort, idempotent).
# Uses the repo's own @aws-sdk/client-s3 (a workspace dep of services/storage),
# resolved via NODE_PATH so no separate `mc` image is needed. BEST-EFFORT: if the
# SDK can't be resolved or MinIO isn't ready, we log and continue — the apps boot
# fine without the bucket; only object-storage operations would fail.
echo "==> ensuring MinIO bucket buildspace-internal ..."
cat > /tmp/ensure-bucket.cjs <<'JS'
const net = require("net");
const { S3Client, CreateBucketCommand } = require("@aws-sdk/client-s3");

function waitForPort(host, port, attempts) {
  return new Promise((resolve) => {
    (function check(n) {
      const s = net.createConnection({ host, port }, () => { s.end(); resolve(true); });
      s.on("error", () => (n <= 0 ? resolve(false) : setTimeout(() => check(n - 1), 1000)));
    })(attempts);
  });
}

(async () => {
  const reachable = await waitForPort("minio", 9000, 60);
  if (!reachable) {
    console.error("minio API not reachable at minio:9000 after ~60s; skipping bucket init");
    process.exit(0);
  }
  console.log("==> minio API reachable");
  const s3 = new S3Client({
    endpoint: "http://minio:9000",
    region: "us-east-1",
    forcePathStyle: true,
    credentials: { accessKeyId: "buildspace", secretAccessKey: "buildspace123" },
  });
  const bucket = "buildspace-internal";
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
      console.error("bucket attempt " + i + "/30: " + name + " (http " + status + "): " + (e && e.message));
    }
    await new Promise((r) => setTimeout(r, 1000));
  }
  console.error("bucket init did not succeed after 30 attempts; continuing anyway (apps will still boot)");
  process.exit(0);
})();
JS
NODE_PATH=/workspace/node_modules bun /tmp/ensure-bucket.cjs \
  || echo "==> bucket init skipped (non-fatal)"

# Launch the whole monorepo dev surface via turbo. We invoke `turbo` directly
# (not `bun dev`) so we can pass --env-mode=loose: turbo.json declares `env` on
# the `build` task, which engages turbo's STRICT env mode and would otherwise
# strip DATABASE_URL (and the rest) from each task — e.g. packages/db's
# `drizzle-kit studio` reads process.env.DATABASE_URL and exits with an empty
# url. `loose` forwards the container's full environment to every task.
echo "==> starting turbo dev (loose env) — all apps"
echo "    marketplace :3000 | runtime :3002 | login :3003 | docs :3004"
echo "    studio :3005 | super-admin :3006 | registry :3008 | jobs :3010"
echo "    (code-review :3007 is internal, used by jobs)"
bunx turbo run dev --env-mode=loose &
PID_DEV=$!

# On stop (SIGTERM from podman) / Ctrl-C, tear the dev servers down and exit 0
# so systemd records a clean stop (inactive, not failed) — which is what lets the
# `PartOf=` cascade stop db & minio. A *natural* crash of turbo skips the trap,
# so `wait` returns non-zero and the container fails loudly instead.
trap 'kill "$PID_DEV" 2>/dev/null || true; exit 0' TERM INT

# Block until turbo exits, then let the container stop.
wait "$PID_DEV"

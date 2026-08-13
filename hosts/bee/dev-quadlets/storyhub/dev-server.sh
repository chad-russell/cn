#!/usr/bin/env bash
#
# dev-server.sh — PID 1 of the storyhub-quadlet app container (bee edition).
#
# On first start it installs deps (whole monorepo, since storyhub + worker +
# storyhub-prisma are interdependent workspace packages), waits for Postgres,
# ensures the MinIO storyhub-media-items bucket exists + CORS, generates the
# Prisma client, runs migrations, then launches the StoryHub web (Next.js :3001)
# and worker (Bun/Hono :8001) dev servers in parallel and blocks until either
# exits — at which point the container stops so you can read the logs and
# restart it manually (systemctl --user restart storyhub-dev-app).
#
# This file is Nix-managed (materialized under /etc/dev-quadlets/storyhub/)
# and bind-mounted read-only into the container at /usr/local/bin/dev-server.sh,
# so nothing is vendored into the hummingbird checkout. StoryHub is reached
# over SSH tunnels (laptop localhost:3001/8001/9000/9001 -> bee:3301/3309/
# 3390/3391; see `cjust dev-tunnel` / `cjust dev-up`), so the apps see localhost.
#
# The worker needs S3_ENDPOINT pointing at the INTERNAL MinIO hostname
# (storyhub-minio:9000) since it downloads files server-side. The web app needs
# S3_ENDPOINT pointing at localhost:9000 since it generates presigned upload
# URLs that the BROWSER must reach. We handle this by overriding S3_ENDPOINT
# inline when launching the worker (below).
set -u

cd /workspace || { echo "FATAL: /workspace not mounted" >&2; exit 1; }

command -v pnpm >/dev/null 2>&1 || corepack enable >/dev/null 2>&1 || true

if [ ! -d node_modules ]; then
  echo "==> first start: pnpm install (whole monorepo)"
  pnpm install --config.dangerously-allow-all-builds=true \
    || { echo "FATAL: pnpm install failed" >&2; exit 1; }
fi

# Wait for Postgres (node TCP check — image has pg_isready from apt but this is
# consistent with the other stacks).
echo "==> waiting for postgres at storyhub-db:5432 ..."
node <<'NODE' || { echo "FATAL: postgres not reachable" >&2; exit 1; }
const net = require("net");
(function check(attempt) {
  const s = net.createConnection({ host: "storyhub-db", port: 5432 }, () => {
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

# Generate Prisma client for storyhub-prisma (both storyhub and worker import it).
echo "==> generating storyhub-prisma client ..."
pnpm --filter storyhub-prisma run prisma:generate || true

# Run StoryHub migrations (deploys committed migrations to the dev DB).
echo "==> running storyhub-prisma migrations ..."
pnpm --filter storyhub-prisma run prisma:migrate:deploy || \
  echo "WARN: prisma migrate deploy failed (may need first-time seed)"

# Ensure the MinIO storyhub-media-items bucket exists + apply CORS. Uses the
# repo's own @aws-sdk/client-s3 (a workspace dep of storyhub). Idempotent.
echo "==> ensuring MinIO bucket storyhub-media-items + CORS ..."
NODE_PATH=/workspace/node_modules node <<'NODE' || { echo "WARN: bucket setup failed (continuing)" >&2; }
const net = require("net");
const { S3Client, CreateBucketCommand, PutBucketCorsCommand } = require("@aws-sdk/client-s3");

function waitForPort(host, port, attempts) {
  return new Promise((resolve) => {
    (function check(n) {
      const s = net.createConnection({ host, port }, () => { s.end(); resolve(true); });
      s.on("error", () => (n <= 0 ? resolve(false) : setTimeout(() => check(n - 1), 1000)));
    })(attempts);
  });
}

(async () => {
  const host = "storyhub-minio";
  const port = 9000;
  const reachable = await waitForPort(host, port, 60);
  if (!reachable) {
    console.error("minio API not reachable at " + host + ":" + port + " after ~60s");
    process.exit(0); // best-effort
  }
  console.log("==> minio API reachable");

  const s3 = new S3Client({
    endpoint: "http://" + host + ":" + port,
    region: "us-east-1",
    forcePathStyle: true,
    credentials: { accessKeyId: "minio", secretAccessKey: "password" },
  });
  const bucket = "storyhub-media-items";

  // Create bucket (idempotent — treat already-exists as success).
  for (let i = 1; i <= 30; i++) {
    try {
      await s3.send(new CreateBucketCommand({ Bucket: bucket }));
      console.log("==> bucket " + bucket + " created");
      break;
    } catch (e) {
      const name = (e && e.name) || "Error";
      const status = (e && e.$metadata && e.$metadata.httpStatusCode) || "-";
      if (name === "BucketAlreadyOwnedByYou" || name === "BucketAlreadyExists" || status === 409) {
        console.log("==> bucket " + bucket + " already exists");
        break;
      }
      console.error("bucket attempt " + i + "/30: " + name + " (http " + status + "): " + (e && e.message));
      if (i === 30) { console.error("giving up on bucket creation"); process.exit(0); }
    }
    await new Promise((r) => setTimeout(r, 1000));
  }

  // Apply CORS so the browser can PUT presigned uploads.
  const corsConfig = {
    CORSRules: [{
      AllowedOrigins: ["http://localhost:3001", "http://localhost:3000"],
      AllowedMethods: ["PUT", "GET", "HEAD", "DELETE"],
      AllowedHeaders: ["*"],
      ExposeHeaders: ["ETag", "x-amz-request-id", "x-amz-version-id"],
      MaxAgeSeconds: 3000,
    }],
  };
  try {
    await s3.send(new PutBucketCorsCommand({ Bucket: bucket, CORSConfiguration: corsConfig }));
    console.log("==> CORS applied to " + bucket);
  } catch (e) {
    console.error("CORS apply failed: " + (e && e.message));
  }
  process.exit(0);
})();
NODE

# Start the worker (Bun/Hono, :8001). Override S3_ENDPOINT to the internal
# hostname — the worker downloads files server-side, so it needs to reach MinIO
# directly on the container network, not via the browser-facing localhost URL.
echo "==> worker -> http://0.0.0.0:8001 (bun, S3 via storyhub-minio:9000)"
cd /workspace/storyhub-worker && \
  S3_ENDPOINT=http://storyhub-minio:9000 \
  DATABASE_URL=postgresql://postgres:postgres@storyhub-db:5432/postgres \
  DIRECT_URL=postgresql://postgres:postgres@storyhub-db:5432/postgres \
  bun --watch server &
PID_WORKER=$!

# Start the web app (Next.js, :3001). S3_ENDPOINT stays as localhost:9000 (from
# the .container env) because the web app generates presigned URLs the browser
# must reach — over the SSH tunnel, localhost:9000 maps to MinIO's published port.
echo "==> web    -> http://0.0.0.0:3001 (next dev, S3 via localhost:9000 for browser presigned URLs)"
cd /workspace/storyhub && pnpm exec next dev --port 3001 -H 0.0.0.0 &
PID_WEB=$!

# On stop (SIGTERM from podman) / Ctrl-C, tear both dev servers down and exit 0.
trap 'kill "$PID_WORKER" "$PID_WEB" 2>/dev/null || true; exit 0' TERM INT

# Block until either dev server exits, then let the container stop.
wait -n "$PID_WORKER" "$PID_WEB"

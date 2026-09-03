#!/usr/bin/env bash
#
# dev-server.sh — PID 1 of the openbible-quadlet app container (bee edition).
#
# Repo: ~/Gloo/open-bible (biblica/open-bible pnpm/Turborepo monorepo).
# Brings up TWO dev servers in one container (like hummingbird/storyhub):
#
#   - Hono API  :9876  (apps/api, tsx watch; PORT=9876 matches the repo
#     docker-compose host-port convention and OPEN_BIBLE_API_BASE_URL)
#   - Payload web :3000 (apps/web, next dev -H 0.0.0.0)
#
# Plus a tiny in-container TCP forwarder localhost:9000 -> openbible-minio:9000.
# Payload's s3Storage plugin uses clientUploads, so S3_ENDPOINT must be
# http://localhost:9000 — the same URL for the BROWSER (reached over the SSH
# tunnel: laptop :9000 -> bee :3402) and the SERVER (through the forwarder).
# Presigned URLs and server-side fetches (image size generation) then work
# from both sides without touching the product repo.
#
# One PostgreSQL serves both schemas (mirrors prod's shared Aurora):
#   Payload `public` (payload migrate + dev push) + Drizzle `api` (migrator).
#
# The ETL app (apps/etl) is intentionally NOT started: it polls the DBL API
# and needs DBL credentials; in the repo it runs as a GitHub-Actions-triggered
# ECS task, not alongside dev.
#
# This file is Nix-managed (materialized under /etc/dev-quadlets/openbible/)
# and bind-mounted read-only into the container, so nothing is vendored into
# the open-bible checkout.
set -u

cd /workspace || { echo "FATAL: /workspace not mounted" >&2; exit 1; }

# The devcontainers/javascript-node image ships pnpm via corepack; enable it if
# `pnpm` isn't already on PATH.
command -v pnpm >/dev/null 2>&1 || corepack enable >/dev/null 2>&1 || true

if [ ! -d node_modules ]; then
  echo "==> first start: pnpm install (whole monorepo)"
  # pnpm-workspace.yaml already allowlists the deps that need build scripts
  # (sharp / esbuild / unrs-resolver), so a plain install runs those and skips
  # the rest — no config overrides needed.
  pnpm install || { echo "FATAL: pnpm install failed" >&2; exit 1; }
fi

# Wait for Postgres (node TCP check — the image has no pg_isready).
echo "==> waiting for postgres at openbible-db:5432 ..."
node <<'NODE' || { echo "FATAL: postgres not reachable" >&2; exit 1; }
const net = require("net");
(function check(attempt) {
  const s = net.createConnection({ host: "openbible-db", port: 5432 }, () => {
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

# --- In-container MinIO forwarder: localhost:9000 -> openbible-minio:9000 ---
# See header. Started BEFORE the apps so S3_ENDPOINT=http://localhost:9000
# works server-side from the first request.
echo "==> minio forwarder: localhost:9000 -> openbible-minio:9000"
node <<'NODE' &
const net = require("net");
net.createServer((client) => {
  const upstream = net.connect({ host: "openbible-minio", port: 9000 });
  client.pipe(upstream).pipe(client);
  const drop = () => { client.destroy(); upstream.destroy(); };
  client.on("error", drop); upstream.on("error", drop);
  client.on("close", () => upstream.destroy());
  upstream.on("close", () => client.destroy());
}).listen(9000, "0.0.0.0", () => console.log("==> forwarder listening on :9000"));
NODE
PID_FWD=$!

# --- Ensure MinIO buckets (idempotent) ------------------------------------
# Two buckets: web media (open-bible-v2-media-items, per apps/web/.env.example)
# and API artifacts (open-bible-artifacts, per the root docker-compose.yml).
# @aws-sdk/client-s3 is a direct dep of @open-bible/api, so node resolves it
# from /workspace/apps/api (pnpm links direct deps per workspace package —
# NODE_PATH at the monorepo root would NOT resolve it).
# No CORS setup needed: recent MinIO auto-answers browser preflights by
# echoing the Origin header, so clientUploads PUTs from localhost:3000 work.
echo "==> ensuring MinIO buckets ..."
cd /workspace/apps/api && node <<'NODE' || { echo "FATAL: MinIO bucket setup failed" >&2; kill "$PID_FWD"; exit 1; }
const { S3Client, CreateBucketCommand } = require("@aws-sdk/client-s3");
const net = require("net");

function waitForPort(host, port, attempts) {
  return new Promise((resolve) => {
    (function check(n) {
      const s = net.createConnection({ host, port }, () => { s.end(); resolve(true); });
      s.on("error", () => (n <= 0 ? resolve(false) : setTimeout(() => check(n - 1), 1000)));
    })(attempts);
  });
}

const s3 = new S3Client({
  endpoint: "http://openbible-minio:9000", // server-side: direct, not via forwarder
  region: "us-east-1",
  forcePathStyle: true,
  credentials: { accessKeyId: "minio", secretAccessKey: "password" },
});
const buckets = ["open-bible-v2-media-items", "open-bible-artifacts"];

(async () => {
  const reachable = await waitForPort("openbible-minio", 9000, 60);
  if (!reachable) {
    console.error("minio API not reachable at openbible-minio:9000 after ~60s");
    process.exit(1);
  }
  console.log("==> minio API reachable");
  for (const bucket of buckets) {
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
        console.error("bucket " + bucket + ": attempt " + i + "/30: " + name + " (http " + status + "): " + (e && e.message));
        if (i === 30) process.exit(1);
      }
      await new Promise((r) => setTimeout(r, 1000));
    }
  }
  process.exit(0);
})();
NODE

# --- Payload dev-migration-row cleanup ------------------------------------
# The dev server's schema push records a `dev` row in payload_migrations; a
# later `payload migrate` then prompts "data loss? (y/N)" on stdin — in a
# non-TTY container that hangs forever with zero DB activity (looks like a
# wedge, isn't). Deleting the row (ignore missing-table on first boot) keeps
# migrate safe to run on every start. Uses postgres.js — a DIRECT dep of
# @open-bible/api (pg is only transitive under pnpm's strict node_modules).
cd /workspace/apps/api && node <<'NODE'
const postgres = require("postgres");
const sql = postgres(process.env.DATABASE_URI, { max: 1 });
sql`delete from payload_migrations where name = 'dev'`
  .then((rows) => {
    if (rows.length > 0) console.log("==> removed " + rows.length + " stale dev migration row(s)");
  })
  .catch((e) => {
    if (e.code !== "42P01") console.error("dev-row cleanup (non-fatal): " + e.message);
  })
  .finally(() => sql.end({ timeout: 5 }).then(() => process.exit(0)));
NODE

# --- Web (Payload) migrations ----------------------------------------------
# Non-fatal on purpose: the dev server pushes schema itself anyway (the repo's
# intended dev flow), reconciling anything migrate can't apply (e.g. drift
# after a dev push). First boot on an empty DB applies cleanly.
echo "==> running payload migrations (web, public schema) ..."
pnpm --filter @open-bible/web payload:migrate \
  || echo "WARN: payload migrate failed (dev server schema-push will reconcile)"

# --- API (Drizzle) migrations ----------------------------------------------
# Library migrator (no spinner) — applies ./src/db/migrations into the `api`
# schema (0000_baseline creates the schema itself). Deterministic (recorded in
# drizzle's own migrations table; nothing else touches the api schema).
echo "==> running drizzle migrations (api schema) ..."
pnpm --filter @open-bible/api migrate \
  || echo "WARN: api migrate failed (API will boot but its routes may error)"

# --- Launch the two dev servers --------------------------------------------
# API (Hono) on :9876. S3_BUCKET overridden inline: the artifacts bucket, not
# the web media bucket from the .container env.
echo "==> api  -> http://0.0.0.0:9876 (tsx watch, artifacts bucket)"
cd /workspace/apps/api && \
  PORT=9876 S3_BUCKET=open-bible-artifacts pnpm dev &
PID_API=$!

# Web (Payload/Next.js) on :3000. `next dev` defaults to localhost, which
# would be invisible outside the container — bind 0.0.0.0.
echo "==> web  -> http://0.0.0.0:3000 (next dev)"
cd /workspace/apps/web && \
  NODE_OPTIONS=--no-deprecation pnpm exec next dev -H 0.0.0.0 -p 3000 &
PID_WEB=$!

# On stop (SIGTERM from podman) / Ctrl-C, tear everything down and exit 0 so
# systemd records a clean stop (inactive, not failed) — which is what lets the
# PartOf= cascade stop db & minio. A natural crash skips the trap, so `wait`
# returns non-zero and the container fails loudly instead.
trap 'kill "$PID_FWD" "$PID_API" "$PID_WEB" 2>/dev/null || true; exit 0' TERM INT

# --- Wait for the web server, then seed ------------------------------------
# Payload pushes schema while the dev server boots, so the seed (which needs
# the tables) must run after :3000 answers. First compile can take a couple of
# minutes on a cold .next; poll up to 4 minutes.
echo "==> waiting for web at localhost:3000 ..."
node <<'NODE'
const http = require("http");
(function check(attempt) {
  const req = http.get("http://localhost:3000", (res) => {
    res.resume();
    console.log("==> web is responding (http " + res.statusCode + ")");
    process.exit(0);
  });
  req.on("error", () => {
    if (attempt >= 120) {
      console.error("web not responding after ~4min (continuing — check logs)");
      process.exit(0);
    }
    setTimeout(() => check(attempt + 1), 2000);
  });
})(0);
NODE

# Seed content pages (idempotent find-or-create; failure is non-fatal — the
# app boots fine without seed data; re-run: pnpm --filter @open-bible/web seed).
echo "==> seeding web content (idempotent) ..."
pnpm --filter @open-bible/web seed \
  || echo "WARN: seed failed (app still up)"

# Block until any process exits, then let the container stop.
wait -n "$PID_FWD" "$PID_API" "$PID_WEB"

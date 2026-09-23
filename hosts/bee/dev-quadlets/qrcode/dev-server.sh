#!/usr/bin/env bash
# PID 1 for the QRCode.Bible review app container.
#
# The app runs a production Next build, not `pnpm dev` (repo hard rule). The
# source tree is bind-mounted at its IDENTICAL host absolute path: Next 16 /
# Turbopack records absolute worktree paths in generated external-module
# aliases; mounting the build at /app makes modules such as generated `pg-*`
# aliases unresolvable.
set -euo pipefail

repo=/home/crussell/Gloo/360-biblica-qr-codes/.worktrees/qrcode-dev
cd "$repo"

# DB and S3 run as sibling Quadlets but publish their established local ports.
# Wait before launching so a stack start/reboot cannot race app initialization.
echo "==> waiting for PostgreSQL localhost:5572 and RustFS localhost:9016 ..."
node <<'NODE'
const net = require('net');
const targets = [
  ['postgres', '127.0.0.1', 5572],
  ['rustfs', '127.0.0.1', 9016],
];
function wait([name, host, port]) {
  return new Promise((resolve, reject) => {
    (function probe(attempt) {
      const s = net.createConnection({ host, port }, () => { s.end(); console.log(`==> ${name} ready`); resolve(); });
      s.on('error', () => attempt >= 120 ? reject(new Error(`${name} unavailable after 120s`)) : setTimeout(() => probe(attempt + 1), 1000));
    })(1);
  });
}
Promise.all(targets.map(wait)).catch((e) => { console.error(e.message); process.exit(1); });
NODE

# Ensure the media bucket exists (idempotent) using the app's own direct AWS SDK
# dependency. RustFS returns 409 when it already exists.
echo "==> ensuring RustFS bucket qrcodes-media ..."
node <<'NODE'
const { S3Client, CreateBucketCommand } = require('@aws-sdk/client-s3');
const s3 = new S3Client({
  endpoint: 'http://127.0.0.1:9016',
  region: 'us-east-1',
  forcePathStyle: true,
  credentials: { accessKeyId: 'minio', secretAccessKey: 'payload123456' },
});
(async () => {
  try {
    await s3.send(new CreateBucketCommand({ Bucket: 'qrcodes-media' }));
    console.log('==> qrcodes-media created');
  } catch (e) {
    const status = e && e.$metadata && e.$metadata.httpStatusCode;
    if (e.name === 'BucketAlreadyOwnedByYou' || e.name === 'BucketAlreadyExists' || status === 409) {
      console.log('==> qrcodes-media already exists');
      return;
    }
    throw e;
  }
})().catch((e) => { console.error('bucket bootstrap failed:', e); process.exit(1); });
NODE

if [ ! -f .next/BUILD_ID ]; then
  echo "FATAL: no production build at $repo/.next — run 'qd qrcode rebuild'" >&2
  exit 1
fi

# Use the image's Node 24 directly. corepack/pnpm wrappers are unnecessary for
# runtime and would add another child process between systemd and next-server.
echo "==> QRCode.Bible -> http://0.0.0.0:3000 (production build)"
exec node node_modules/next/dist/bin/next start -H 0.0.0.0 -p 3000

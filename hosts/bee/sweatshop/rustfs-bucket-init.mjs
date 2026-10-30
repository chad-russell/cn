// Skills-bucket bootstrap for sweatshop-rustfs (0088 skills store).
// Runs INSIDE a one-off container on sweatshop-harness (the sidecar
// publishes nothing; only harness members can reach it), driven by
// the NixOS-generated user unit in sweatshop.nix (sweatshop-db-
// snapshot mechanics). Uses the app's own image + its bundled
// @aws-sdk/client-s3 — the same client, same path-style addressing,
// same auth the app's s3Gateway uses (lib/skills/store.ts), so a
// green run proves the app's exact access path end-to-end.
//
// Creds: RUSTFS_ACCESS_KEY/RUSTFS_SECRET_KEY env (agenix
// sweatshop-rustfs-env, same values the sidecar runs with).

const endpoint = process.env.SKILLS_S3_ENDPOINT ?? "http://sweatshop-rustfs:9000";
const bucket = process.env.SKILLS_S3_BUCKET ?? "skills";

const { S3Client, HeadBucketCommand, CreateBucketCommand } = await import("@aws-sdk/client-s3");
const client = new S3Client({
  endpoint,
  region: process.env.SKILLS_S3_REGION ?? "us-east-1",
  forcePathStyle: true,
  credentials: {
    accessKeyId: process.env.RUSTFS_ACCESS_KEY ?? "",
    secretAccessKey: process.env.RUSTFS_SECRET_KEY ?? "",
  },
});

const has = () =>
  client.send(new HeadBucketCommand({ Bucket: bucket })).then(
    () => true,
    () => false,
  );

for (let i = 1; i <= 30; i++) {
  if (await has()) {
    console.log(`bucket ${bucket} present at ${endpoint}`);
    process.exit(0);
  }
  try {
    await client.send(new CreateBucketCommand({ Bucket: bucket }));
    console.log(`bucket ${bucket} created at ${endpoint}`);
    process.exit(0);
  } catch {
    // not ready yet (or transiently refused) — retry below
  }
  await new Promise((r) => setTimeout(r, 10000));
}
console.error(`${endpoint} never became ready`);
process.exit(1);

#!/usr/bin/env bash
# Initialize S3 buckets in RustFS.
# Uses the aws cli container with --network host since RustFS is on localhost.
set -euo pipefail

AWS_CLI_IMAGE="${AWS_CLI_IMAGE:-docker.io/amazon/aws-cli:latest}"
ENDPOINT_URL="${S3_ENDPOINT_URL:-http://127.0.0.1:9000}"
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-rustfsadmin}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-rustfsadmin}"
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

BUCKETS=(
  gpl-assets
  storyhub-media-items
  polymer-bucket
)

echo "Waiting for RustFS at $ENDPOINT_URL..."
for i in $(seq 1 30); do
  if podman run --rm --network host \
    -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
    -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
    -e AWS_DEFAULT_REGION="$AWS_DEFAULT_REGION" \
    "$AWS_CLI_IMAGE" \
    s3api list-buckets --endpoint-url "$ENDPOINT_URL" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! podman run --rm --network host \
  -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
  -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
  -e AWS_DEFAULT_REGION="$AWS_DEFAULT_REGION" \
  "$AWS_CLI_IMAGE" \
  s3api list-buckets --endpoint-url "$ENDPOINT_URL" >/dev/null 2>&1; then
  echo "ERROR: RustFS did not become ready at $ENDPOINT_URL" >&2
  exit 1
fi

echo "Creating buckets..."
for b in "${BUCKETS[@]}"; do
  if podman run --rm --network host \
    -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
    -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
    -e AWS_DEFAULT_REGION="$AWS_DEFAULT_REGION" \
    "$AWS_CLI_IMAGE" \
    s3api create-bucket --bucket "$b" --endpoint-url "$ENDPOINT_URL" >/dev/null 2>&1; then
    echo "  ✓ $b"
  fi
done

echo "Done."

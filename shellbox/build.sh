#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p target-host

podman run --rm \
  -v "$PWD":/src:Z \
  -w /src \
  docker.io/library/rust:1-bookworm \
  bash -lc 'export PATH="$PATH:/usr/local/cargo/bin:/root/.cargo/bin"; command -v cargo >/dev/null; cargo build --release'

cp -f target/release/shellbox "$HOME/.local/bin/shellbox"

echo "built: $PWD/target-host/shellbox"

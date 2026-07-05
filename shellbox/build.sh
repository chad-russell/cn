#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p target-host

# Build the shellbox CLI. Uses podman so the build environment is reproducible
# without a local Rust toolchain.
podman run --rm \
  -v "$PWD":/src:Z \
  -w /src \
  docker.io/library/rust:1-bookworm \
  bash -lc 'export PATH="$PATH:/usr/local/cargo/bin:/root/.cargo/bin"; command -v cargo >/dev/null; cargo build --release'

cp -f target/release/shellbox target-host/shellbox
cp -f target/release/shellbox "$HOME/.local/bin/shellbox"

echo "built: $PWD/target-host/shellbox"

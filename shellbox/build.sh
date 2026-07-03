#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p target-host

# Build the whole workspace (both the `shellbox` CLI and the
# `shellbox-host-exec` in-box helper). `--workspace` is required because the
# repo root is itself a package, so a bare `cargo build` would only build
# `shellbox` and skip the helper member. The helper is a separate zero-dep
# crate so it can later be built statically (musl) for cross-distro boxes
# without dragging in shellbox's heavy dependency tree.
podman run --rm \
  -v "$PWD":/src:Z \
  -w /src \
  docker.io/library/rust:1-bookworm \
  bash -lc 'export PATH="$PATH:/usr/local/cargo/bin:/root/.cargo/bin"; command -v cargo >/dev/null; cargo build --release --workspace'

cp -f target/release/shellbox target-host/shellbox
cp -f target/release/shellbox "$HOME/.local/bin/shellbox"

# Install the helper alongside shellbox; `shellbox` finds it by looking next to
# its own executable at runtime.
cp -f target/release/shellbox-host-exec target-host/shellbox-host-exec
cp -f target/release/shellbox-host-exec "$HOME/.local/bin/shellbox-host-exec"

echo "built: $PWD/target-host/shellbox"
echo "built: $PWD/target-host/shellbox-host-exec"

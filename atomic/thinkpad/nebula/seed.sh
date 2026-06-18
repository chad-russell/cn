#!/usr/bin/env bash
# Seed (or re-seed) the rootful 'nebula-config' podman volume with
# config.yaml + certs, decrypting the private key from the repo's
# age-encrypted nebula/pki/thinkpad.key.age.
#
# Per the repo convention (see AGENTS.md "Nebula VPN"), nebula PKI
# *.key.age files are encrypted to the SSH ed25519 key, NOT the age
# keys.txt (which is for the old home-manager secrets). So the default
# identity is ~/.ssh/id_ed25519.
#
# `age` is NOT assumed to be installed on the host — decryption happens
# inside a throwaway alpine container.
#
# Safe to re-run any time config.yaml or certs change. Does NOT touch the
# nebula service (use `systemctl restart nebula` after re-seeding).
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SELF_DIR/../../.." && pwd)"   # atomic/thinkpad/nebula -> repo root
PKI="$REPO/nebula/pki"
CFG="$SELF_DIR/config.yaml"
NEBULA_IDENTITY="${NEBULA_IDENTITY:-$HOME/.ssh/id_ed25519}"
VOLUME="nebula-config"
ALPINE="docker.io/alpine:latest"

for f in "$NEBULA_IDENTITY" "$CFG" "$PKI/ca.crt" "$PKI/thinkpad.crt" "$PKI/thinkpad.key.age"; do
  [ -f "$f" ] || { echo "missing required file: $f" >&2; exit 1; }
done

sudo -v

# Stage all inputs into a private temp dir. We bind-mount ONLY this temp dir
# into the decrypt container, so repo files and the real identity key are
# never relabeled by SELinux (:Z only touches the temp copies).
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
chmod 700 "$STAGE"
cp "$CFG" "$STAGE/config.yaml"
cp "$PKI/ca.crt" "$STAGE/ca.crt"
cp "$PKI/thinkpad.crt" "$STAGE/host.crt"
cp "$PKI/thinkpad.key.age" "$STAGE/host.key.age"
cp "$NEBULA_IDENTITY" "$STAGE/identity"
chmod 600 "$STAGE/identity" "$STAGE/host.key.age"

# Ensure the volume exists.
sudo podman volume exists "$VOLUME" 2>/dev/null || sudo podman volume create "$VOLUME"

# Decrypt the key and write all files into the volume, in one throwaway container.
sudo podman run --rm \
  -v "$VOLUME:/out" \
  -v "$STAGE:/in:ro,Z" \
  "$ALPINE" sh -c '
    set -e
    apk add --no-cache age >/dev/null
    age -d -i /in/identity /in/host.key.age > /out/host.key
    cp /in/config.yaml /out/config.yaml
    cp /in/ca.crt /out/ca.crt
    cp /in/host.crt /out/host.crt
    chmod 600 /out/host.key
    chmod 644 /out/config.yaml /out/ca.crt /out/host.crt
    echo "Contents of volume:"
    ls -l /out
  '

echo "Seeded volume '$VOLUME'."
echo "Restart the service to pick up changes:  sudo systemctl restart nebula"

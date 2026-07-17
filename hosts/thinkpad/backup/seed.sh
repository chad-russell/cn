#!/usr/bin/env bash
# Seed /etc/restic-backup/ with the restic repo password + S3 creds, decrypted
# from the repo's age-encrypted secrets. Mirrors nebula/seed.sh.
#
# Identity: ~/.config/age/key.txt  (the fleet age identity — see README; copy
# it from bees once. NOT the SSH key: secrets/*.age are encrypted to the age
# public key, unlike nebula PKI which uses the SSH ed25519 key.)
#
# `age` is NOT assumed on the host — decryption happens in an alpine container.
# Safe to re-run any time the secrets or excludes change. Does NOT touch the
# running timers/services.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SELF_DIR/../../.." && pwd)"   # hosts/thinkpad/backup -> repo root
SECRETS="$REPO/secrets"
# Resolve the *invoking* user's home even if run under sudo (where $HOME=/root).
INVOKER="${SUDO_USER:-${USER:-$(id -un)}}"
INVOKER_HOME="$(getent passwd "$INVOKER" | cut -d: -f6)"
IDENTITY="${RESTIC_IDENTITY:-$INVOKER_HOME/.config/age/key.txt}"
DEST="/etc/restic-backup"
ALPINE="docker.io/library/alpine:latest"

if [ ! -f "$IDENTITY" ]; then
  cat >&2 <<EOF
ERROR: age identity not found at $IDENTITY

The repo secrets (secrets/*.age) are encrypted to the fleet age public key, so
think needs the matching private key. Copy it from bees (one-time, like the
nas/gateway step in AGENTS.md):

  ssh -o IdentitiesOnly=yes crussell@10.10.0.6 \\
    'cat ~/.config/age/key.txt' | sudo tee "$IDENTITY" >/dev/null
  sudo chmod 600 "$IDENTITY"
EOF
  exit 1
fi

for f in "$SECRETS/restic-password-think.age" "$SECRETS/restic-s3-credentials.age" "$SELF_DIR/excludes"; do
  [ -f "$f" ] || { echo "missing required file: $f" >&2; exit 1; }
done

sudo -v

# Stage all inputs into a private temp dir; bind ONLY this dir into the decrypt
# container so repo files and the identity are never relabeled.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
chmod 700 "$STAGE"
cp "$IDENTITY" "$STAGE/identity"
cp "$SECRETS/restic-password-think.age" "$STAGE/password.age"
cp "$SECRETS/restic-s3-credentials.age" "$STAGE/s3-creds.age"
cp "$SELF_DIR/excludes" "$STAGE/excludes"
chmod 600 "$STAGE/identity" "$STAGE"/*.age

sudo install -d -m 700 "$DEST"

# Decrypt into /etc/restic-backup in one throwaway container.
sudo podman run --rm \
  -v "$DEST:/out" \
  -v "$STAGE:/in:ro,Z" \
  "$ALPINE" sh -c '
    set -e
    apk add --no-cache age >/dev/null
    age -d -i /in/identity /in/password.age > /out/password
    age -d -i /in/identity /in/s3-creds.age  > /out/s3.env
    cp /in/excludes /out/excludes
    chmod 600 /out/password /out/s3.env
    chmod 644 /out/excludes
    echo "Seeded into /etc/restic-backup:"
    ls -l /out
  '

echo
echo "Seeded $DEST."

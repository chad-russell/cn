#!/usr/bin/env bash
# Diagnostic: is thinkpad.crt a valid nebula cert, and is the decrypted
# host.key the right shape? Prints CA / thinkpad / bees cert structure via
# `nebula-cert print` (which is inside the already-built
# localhost/nebula:thinkpad image).
#
# Prints sizes + PEM headers + nebula-cert's parse output. Does NOT print
# private key material — only the decrypted key's size and first line.
#
# Run on the host:
#   cd ~/Code/cn/atomic/thinkpad/nebula && ./debug.sh
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SELF_DIR/../../.." && pwd)"
PKI="$REPO/nebula/pki"
IMAGE="localhost/nebula:thinkpad"

# Sanity
for f in "$PKI/ca.crt" "$PKI/thinkpad.crt" "$PKI/bees.crt" \
         "$PKI/thinkpad.key.age" "$HOME/.ssh/id_ed25519"; do
  [ -f "$f" ] || { echo "missing: $f" >&2; exit 1; }
done

# Stage identity + encrypted key into a private temp dir.
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
chmod 700 "$STAGE"
cp "$HOME/.ssh/id_ed25519" "$STAGE/identity"; chmod 600 "$STAGE/identity"
cp "$PKI/thinkpad.key.age" "$STAGE/host.key.age"
# Copy certs into the throwaway stage too, so we only mount the stage dir
# (avoids SELinux-relabeling the repo's tracked pki files).
cp "$PKI/ca.crt"       "$STAGE/ca.crt"
cp "$PKI/thinkpad.crt" "$STAGE/thinkpad.crt"
cp "$PKI/bees.crt"     "$STAGE/bees.crt"

sudo -v

echo "Using image: $IMAGE"
echo "(Mounting only a private temp stage dir.)"
echo

sudo podman run --rm \
  --entrypoint /bin/sh \
  -v "$STAGE:/stage:Z" \
  "$IMAGE" -c '
    set -e
    apk add --no-cache age >/dev/null 2>&1

    echo "############ KEY CHECK (size + first line only) ############"
    age -d -i /stage/identity /stage/host.key.age > /stage/host.key
    echo "decrypted host.key: $(wc -c < /stage/host.key) bytes"
    echo "first line:         $(head -1 /stage/host.key)"
    echo

    echo "############ CA (ca.crt) ############"
    nebula-cert print -path /stage/ca.crt 2>&1 | head -15
    echo

    echo "############ thinkpad.crt (THE SUSPECT) ############"
    nebula-cert print -path /stage/thinkpad.crt 2>&1 | head -15
    echo

    echo "############ bees.crt (CONTROL — known good) ############"
    nebula-cert print -path /stage/bees.crt 2>&1 | head -15
  '

echo
echo "Done. If thinkpad.crt failed to print while bees.crt succeeded, the cert"
echo "in the repo is corrupt/stale and needs regenerating from the CA."

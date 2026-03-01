#!/bin/bash
# Nebula certificate generator helper
# Usage: ./gen-certs.sh <hostname> <overlay-ip> <groups>

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKI_DIR="${SCRIPT_DIR}/../pki"

# Check for CA
if [[ ! -f "$PKI_DIR/ca.crt" || ! -f "$PKI_DIR/ca.key" ]]; then
    echo "ERROR: CA not found in $PKI_DIR"
    echo "Run: ./init-ca.sh first"
    exit 1
fi

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <hostname> <overlay-ip> [groups]"
    echo "Example: $0 k1 10.10.0.4 servers,media"
    exit 1
fi

HOSTNAME="$1"
IP="$2"
GROUPS="${3:-servers}"

# Validate IP format
if ! [[ "$IP" =~ ^10\.10\.0\.[0-9]+$ ]]; then
    echo "ERROR: IP must be in 10.10.0.x range"
    exit 1
fi

echo "Generating certificate for: $HOSTNAME"
echo "  IP: $IP/24"
echo "  Groups: $GROUPS"

cd "$PKI_DIR"

../nebula-cert sign \
    -name "$HOSTNAME" \
    -ip "$IP/24" \
    -groups "$GROUPS" \
    -out-crt "$HOSTNAME.crt" \
    -out-key "$HOSTNAME.key" \
    -ca-crt ca.crt \
    -ca-key ca.key \
    -duration 8760h  # 1 year

echo ""
echo "Generated:"
echo "  $PKI_DIR/$HOSTNAME.crt"
echo "  $PKI_DIR/$HOSTNAME.key"
echo ""
echo "Deploy with: ca.crt, $HOSTNAME.crt, $HOSTNAME.key"

#!/bin/bash
# Initialize Nebula CA
# Run once to create the Certificate Authority

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKI_DIR="${SCRIPT_DIR}/../pki"

mkdir -p "$PKI_DIR"
cd "$PKI_DIR"

# Download nebula-cert if not present
if [[ ! -f "$SCRIPT_DIR/nebula-cert" ]]; then
    echo "Downloading nebula-cert..."
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        arm64) ARCH="arm64" ;;
        *) echo "Unknown arch: $ARCH"; exit 1 ;;
    esac
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    curl -Lo "$SCRIPT_DIR/nebula-cert" "https://github.com/slackhq/nebula/releases/download/v1.9.5/nebula-cert-$OS-$ARCH"
    chmod +x "$SCRIPT_DIR/nebula-cert"
fi

if [[ -f ca.crt ]]; then
    echo "WARNING: CA already exists in $PKI_DIR"
    echo "Delete ca.crt and ca.key to regenerate (OLD HOSTS WILL NEED NEW CERTS)"
    read -p "Continue anyway? (y/N) " -n1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo ""
echo "Creating Nebula CA..."
echo "This CA will be valid for 10 years."
echo ""

read -p "CA Name (e.g., 'Crussell Homelab'): " CA_NAME
if [[ -z "$CA_NAME" ]]; then
    CA_NAME="Crussell Nebula CA"
fi

"$SCRIPT_DIR/nebula-cert" ca \
    -name "$CA_NAME" \
    -out-crt ca.crt \
    -out-key ca.key \
    -duration 87600h  # 10 years

echo ""
echo "=========================================="
echo "CA created successfully!"
echo "=========================================="
echo ""
echo "Files:"
echo "  $PKI_DIR/ca.crt - Public certificate (can distribute)"
echo "  $PKI_DIR/ca.key - PRIVATE KEY (KEEP SECURE!)"
echo ""
echo "NEXT STEPS:"
echo "1. Backup CA to Bitwarden:"
echo "   tar czvf - ca.crt ca.key | gpg --symmetric --cipher-algo AES256 -o nebula-ca.tar.gz.gpg"
echo ""
echo "2. Generate host certificates with:"
echo "   ./gen-certs.sh <hostname> <ip> <groups>"

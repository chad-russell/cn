#!/usr/bin/env bash
set -euo pipefail

echo "=== Creating /srv directory structure ==="

sudo mkdir -p /srv/beszel
sudo chown -R $(id -u):$(id -g) /srv/beszel

echo "=== Decrypting secrets ==="

AGE_KEY="${HOME}/.config/age/key.txt"
SECRETS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/secrets"

if [[ ! -f "$AGE_KEY" ]]; then
    echo "ERROR: Age key not found at $AGE_KEY"
    echo "Please create an age key first or copy your existing key to that location."
    exit 1
fi

if ! command -v age &>/dev/null; then
    echo "ERROR: age command not found. Please install age:"
    echo "  https://github.com/FiloSottile/age#installation"
    exit 1
fi

age -d -i "$AGE_KEY" "$SECRETS_DIR/beszel-media.env.age" > /srv/beszel/secrets.env
chmod 600 /srv/beszel/secrets.env

echo "=== Copying quadlet files ==="

mkdir -p ~/.config/containers/systemd

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for f in "$SCRIPT_DIR"/containers/*.container; do
    [ -f "$f" ] && cp "$f" ~/.config/containers/systemd/
done

echo "=== Enabling lingering for user services ==="
sudo loginctl enable-linger $(whoami)

echo "=== Reloading systemd ==="
systemctl --user daemon-reload

echo ""
echo "=== Setup complete! ==="
echo ""
echo "Start the Beszel agent:"
echo "  systemctl --user enable --now beszel-agent"

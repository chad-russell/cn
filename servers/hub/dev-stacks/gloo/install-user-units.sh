#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="$(cd "$(dirname "$0")" && pwd)"
UNIT_SRC_DIR="$STACK_DIR/systemd/units"
UNIT_DEST_DIR="$HOME/.config/systemd/user"

mkdir -p "$UNIT_DEST_DIR"

for unit in "$UNIT_SRC_DIR"/*; do
  ln -sfn "$unit" "$UNIT_DEST_DIR/$(basename "$unit")"
done

systemctl --user daemon-reload

echo "Installed user units:"
ls -1 "$UNIT_SRC_DIR"

echo
echo "Examples:"
echo "  systemctl --user start gloo-gpl.service"
echo "  systemctl --user start gloo-hummingbird.target"
echo "  systemctl --user start gloo-storyhub.target"
echo "  systemctl --user start gloo-all.target"
echo "  systemctl --user status gloo-polymer.service"
echo "  journalctl --user -u gloo-polymer.service -f"

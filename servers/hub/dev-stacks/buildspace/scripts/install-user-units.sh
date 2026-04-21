#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
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
echo "  systemctl --user start buildspace.target"
echo "  systemctl --user start buildspace-marketplace.service"
echo "  systemctl --user start buildspace-runtime.service"
echo "  systemctl --user status buildspace.target"
echo "  journalctl --user -u buildspace-runtime.service -f"

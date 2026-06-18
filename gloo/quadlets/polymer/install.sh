#!/usr/bin/env bash
#
# install.sh — link the polymer quadlet dev stack into the user systemd quadlet
# search path (~/.config/containers/systemd/) and reload systemd.
#
# Idempotent. Re-run after editing any *.container / *.volume / *.network / *.build.
#
# Works from the host, the `cdev` toolbox, or a plain toolbox (it reaches
# systemctl on the host via flatpak-spawn when needed).
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd"

if command -v systemctl >/dev/null 2>&1; then
  SYS=(systemctl --user)
elif command -v flatpak-spawn >/dev/null 2>&1; then
  SYS=(flatpak-spawn --host systemctl --user)
else
  echo "FATAL: no systemctl found (run on the host or a toolbox with flatpak-spawn)" >&2
  exit 1
fi

mkdir -p "$DEST"

echo "==> symlinking quadlet units into $DEST"
for f in "$SELF_DIR"/*.container "$SELF_DIR"/*.volume "$SELF_DIR"/*.network "$SELF_DIR"/*.build; do
  [ -e "$f" ] || continue
  name="$(basename "$f")"
  ln -sfn "$f" "$DEST/$name"
  echo "    $DEST/$name -> $f"
done

echo "==> systemctl --user daemon-reload"
"${SYS[@]}" daemon-reload

echo
echo "==> generated units:"
"${SYS[@]}" list-unit-files 'polymer-dev*' 2>/dev/null || true

cat <<EOF

Done. Start the stack:
  ${SYS[*]} start polymer-dev-app
Stop it:
  ${SYS[*]} stop polymer-dev-app
Follow the app logs:
  ${SYS[*]} status polymer-dev-app   # or: journalctl --user -u polymer-dev-app -f

Browser: http://localhost:3000 (polymer)  http://localhost:3001 (admin360)
EOF

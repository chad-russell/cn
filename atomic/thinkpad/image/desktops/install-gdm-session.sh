#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

TARGET_BIN="/usr/local/bin/niri-bwrap-session"
TARGET_DESKTOP_DIR="/usr/local/share/wayland-sessions"
TARGET_DESKTOP="${TARGET_DESKTOP_DIR}/niri-bwrap.desktop"
SOURCE_LAUNCHER="${SCRIPT_DIR}/launch-bwrap-session.sh"

sudo install -d /usr/local/bin "$TARGET_DESKTOP_DIR"
sudo tee "$TARGET_BIN" >/dev/null <<EOF
#!/usr/bin/env bash
exec "$SOURCE_LAUNCHER" "\$@"
EOF
sudo chmod 0755 "$TARGET_BIN"
sudo install -m 0644 "${IMAGE_DIR}/niri-bwrap.desktop" "$TARGET_DESKTOP"

cat <<EOF
Installed:
  launcher: $TARGET_BIN (wrapper for ${SOURCE_LAUNCHER})
  desktop:  $TARGET_DESKTOP

Log out, click your user in GDM, then look for the gear icon.
EOF

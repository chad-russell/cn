#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_USER="${OPENCLAW_USER:-openclaw}"
OPENCLAW_HOME="/home/${OPENCLAW_USER}"
OPENCLAW_CONFIG_DIR="/srv/openclaw/config"
OPENCLAW_WORKSPACE_DIR="/srv/openclaw/workspace"
OPENCLAW_SANDBOX_DIR="/srv/openclaw/sandboxes"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing dependency: %s\n' "$1" >&2
    exit 1
  fi
}

run_as_openclaw() {
  sudo -u "$OPENCLAW_USER" env HOME="$OPENCLAW_HOME" bash -lc 'cd "$HOME" && exec "$@"' bash "$@"
}

generate_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
    return
  fi

  python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
}

require_cmd sudo
require_cmd podman
require_cmd python3
require_cmd systemctl
require_cmd loginctl

if ! id -u "$OPENCLAW_USER" >/dev/null 2>&1; then
  sudo useradd --create-home --home-dir "$OPENCLAW_HOME" --shell /usr/sbin/nologin "$OPENCLAW_USER"
fi

OPENCLAW_UID="$(id -u "$OPENCLAW_USER")"
PODMAN_SOCKET="/run/user/${OPENCLAW_UID}/podman/podman.sock"

if ! grep -q "^${OPENCLAW_USER}:" /etc/subuid 2>/dev/null; then
  printf 'Warning: %s has no subuid range in /etc/subuid. Rootless Podman may fail.\n' "$OPENCLAW_USER" >&2
fi

if ! grep -q "^${OPENCLAW_USER}:" /etc/subgid 2>/dev/null; then
  printf 'Warning: %s has no subgid range in /etc/subgid. Rootless Podman may fail.\n' "$OPENCLAW_USER" >&2
fi

sudo loginctl enable-linger "$OPENCLAW_USER"
sudo systemctl start "user@${OPENCLAW_UID}.service" || true
sudo systemctl --machine "${OPENCLAW_USER}@" --user enable --now podman.socket

sudo mkdir -p "$OPENCLAW_CONFIG_DIR" "$OPENCLAW_WORKSPACE_DIR" "$OPENCLAW_SANDBOX_DIR"
sudo chown -R "$OPENCLAW_USER:$OPENCLAW_USER" /srv/openclaw
sudo chmod 700 "$OPENCLAW_CONFIG_DIR" "$OPENCLAW_WORKSPACE_DIR" "$OPENCLAW_SANDBOX_DIR"

if [[ ! -f "$OPENCLAW_CONFIG_DIR/openclaw.json" ]]; then
  sudo install -o "$OPENCLAW_USER" -g "$OPENCLAW_USER" -m 600 "$SCRIPT_DIR/openclaw.json" "$OPENCLAW_CONFIG_DIR/openclaw.json"
fi

if [[ ! -f "$OPENCLAW_CONFIG_DIR/.env" ]]; then
  sudo install -o "$OPENCLAW_USER" -g "$OPENCLAW_USER" -m 600 "$SCRIPT_DIR/openclaw.env.example" "$OPENCLAW_CONFIG_DIR/.env"
fi

if ! sudo grep -q '^OPENCLAW_GATEWAY_TOKEN=' "$OPENCLAW_CONFIG_DIR/.env"; then
  printf 'OPENCLAW_GATEWAY_TOKEN=%s\n' "$(generate_token)" | sudo tee -a "$OPENCLAW_CONFIG_DIR/.env" >/dev/null
fi

if sudo grep -q '^OPENCLAW_GATEWAY_TOKEN=replace-with-generated-token$' "$OPENCLAW_CONFIG_DIR/.env"; then
  sudo python3 - "$OPENCLAW_CONFIG_DIR/.env" "$(generate_token)" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
token = sys.argv[2]
text = path.read_text()
text = text.replace('OPENCLAW_GATEWAY_TOKEN=replace-with-generated-token', f'OPENCLAW_GATEWAY_TOKEN={token}', 1)
path.write_text(text)
PY
fi

sudo chown "$OPENCLAW_USER:$OPENCLAW_USER" "$OPENCLAW_CONFIG_DIR/.env"
sudo chmod 600 "$OPENCLAW_CONFIG_DIR/.env"

BUILD_STAGING_DIR="$(mktemp -d /var/tmp/openclaw-build.XXXXXX)"
trap 'sudo rm -rf "$BUILD_STAGING_DIR"' EXIT
sudo cp -a "$SCRIPT_DIR/images/." "$BUILD_STAGING_DIR/"
sudo chown -R "$OPENCLAW_USER:$OPENCLAW_USER" "$BUILD_STAGING_DIR"

run_as_openclaw podman build -t localhost/openclaw-hub:latest -f "$BUILD_STAGING_DIR/Containerfile" "$BUILD_STAGING_DIR"
run_as_openclaw podman build -t openclaw-sandbox:bookworm-slim -f "$BUILD_STAGING_DIR/Dockerfile.sandbox" "$BUILD_STAGING_DIR"
run_as_openclaw podman build -t openclaw-sandbox-browser:bookworm-slim -f "$BUILD_STAGING_DIR/Dockerfile.sandbox-browser" "$BUILD_STAGING_DIR"

run_as_openclaw mkdir -p "$OPENCLAW_HOME/.config/containers/systemd"
sudo python3 - "$SCRIPT_DIR/openclaw.container.in" "$OPENCLAW_HOME/.config/containers/systemd/openclaw.container" "$PODMAN_SOCKET" <<'PY'
from pathlib import Path
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
podman_socket = sys.argv[3]
text = src.read_text().replace('{{PODMAN_SOCKET}}', podman_socket)
dst.write_text(text)
PY
sudo chown "$OPENCLAW_USER:$OPENCLAW_USER" "$OPENCLAW_HOME/.config/containers/systemd/openclaw.container"
sudo chmod 600 "$OPENCLAW_HOME/.config/containers/systemd/openclaw.container"

sudo systemctl --machine "${OPENCLAW_USER}@" --user daemon-reload
sudo systemctl --machine "${OPENCLAW_USER}@" --user start openclaw.service

printf '\nOpenClaw installed.\n'
printf 'Update %s with TELEGRAM_BOT_TOKEN and model-provider credentials.\n' "$OPENCLAW_CONFIG_DIR/.env"
printf 'Service status: sudo systemctl --machine %s@ --user status openclaw.service\n' "$OPENCLAW_USER"

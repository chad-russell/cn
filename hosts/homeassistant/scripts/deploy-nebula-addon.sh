#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PKI_DIR="$REPO_ROOT/nebula/pki"
ADDON_DIR="$REPO_ROOT/hosts/homeassistant/addons/nebula"
HA_HOST="${HA_HAOS_HOST:-192.168.20.51}"
HA_USER="${HA_HAOS_USER:-hassio}"

if [ -z "${HA_SSH_PASSWORD:-}" ]; then
    echo "ERROR: HA_SSH_PASSWORD not set" >&2
    echo "Usage: HA_SSH_PASSWORD=<pw> $0" >&2
    exit 1
fi

askpass_file="$(mktemp)"
trap 'rm -f "$askpass_file"' EXIT
cat >"$askpass_file" <<ASKPASS
#!/bin/sh
printf '%s\n' '${HA_SSH_PASSWORD}'
ASKPASS
chmod 700 "$askpass_file"

ssh_ha() {
    env DISPLAY=:0 SSH_ASKPASS="$askpass_file" SSH_ASKPASS_REQUIRE=force \
        setsid ssh -o IdentitiesOnly=yes -o PreferredAuthentications=password \
        -o PubkeyAuthentication=no \
        "$HA_USER@$HA_HOST" "$@"
}

echo "=== Nebula Standalone Container Deploy ==="
echo "HA target: $HA_USER@$HA_HOST"
echo ""

if [ ! -f "$PKI_DIR/homeassistant.crt" ] || [ ! -f "$PKI_DIR/homeassistant.key" ]; then
    echo "ERROR: Certs not found at $PKI_DIR/homeassistant.{crt,key}" >&2
    exit 1
fi

echo "==> Preparing build context"
ssh_ha 'mkdir -p /tmp/nebula-build'
ssh_ha "cat > /tmp/nebula-build/Dockerfile" << 'DOCKERFILE'
FROM alpine:3.21
RUN apk add --no-cache curl && \
    curl -fSL "https://github.com/slackhq/nebula/releases/download/v1.10.3/nebula-linux-amd64.tar.gz" | tar xz -C /usr/bin/ && \
    chmod 755 /usr/bin/nebula /usr/bin/nebula-cert
COPY nebula.yaml /etc/nebula/config.yaml
COPY ca.crt /ssl/nebula/ca.crt
COPY homeassistant.crt /ssl/nebula/host.crt
COPY homeassistant.key /ssl/nebula/host.key
RUN chmod 600 /ssl/nebula/host.key
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
DOCKERFILE

ssh_ha "cat > /tmp/nebula-build/entrypoint.sh" << 'ENTRY'
#!/bin/sh
set -e
mkdir -p /dev/net
[ ! -c /dev/net/tun ] && mknod /dev/net/tun c 10 200 && chmod 600 /dev/net/tun
echo "[Nebula] Starting VPN client (10.10.0.51)"
exec nebula -config /etc/nebula/config.yaml
ENTRY

echo "==> Transferring files"
ADDON_TAR="$(mktemp)"
trap 'rm -f "$askpass_file" "$ADDON_TAR"' EXIT
tar cf "$ADDON_TAR" -C "$ADDON_DIR" nebula.yaml
tar rf "$ADDON_TAR" -C "$PKI_DIR" ca.crt homeassistant.crt homeassistant.key
ssh_ha "cat > /tmp/nebula-deploy.tar" < "$ADDON_TAR"

echo "==> Extracting and building image"
ssh_ha 'cd /tmp && tar xf nebula-deploy.tar -C nebula-build/ && \
    sudo docker build -t nebula-standalone /tmp/nebula-build/ 2>&1 | tail -3'

echo "==> Restarting container"
ssh_ha 'sudo docker rm -f nebula 2>/dev/null; \
    sudo docker run -d \
        --name nebula \
        --restart=always \
        --net=host \
        --cap-add=NET_ADMIN \
        --privileged \
        nebula-standalone && \
    sleep 4 && \
    sudo docker logs nebula 2>&1 | tail -5'

echo ""
echo "=== Deploy complete ==="
echo "Verify: $SCRIPT_DIR/ha-ssh.sh 'ping -c 3 10.10.0.6'"

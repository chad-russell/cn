#!/usr/bin/bash
set -e

echo "[Nebula] Creating TUN device if needed"
mkdir -p /dev/net
if [ ! -c /dev/net/tun ]; then
    mknod /dev/net/tun c 10 200
    chmod 600 /dev/net/tun
fi

echo "[Nebula] Starting VPN client (10.10.0.51)"
exec nebula -config /etc/nebula/config.yaml 2>&1

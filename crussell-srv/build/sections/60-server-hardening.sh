#!/usr/bin/env bash

set -eoux pipefail

echo "::group:: Server Hardening (Optional)"

dnf5 install -y firewalld 2>/dev/null || true
systemctl enable firewalld

echo "::endgroup::"

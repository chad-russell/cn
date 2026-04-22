#!/usr/bin/env bash

set -eoux pipefail

echo "::group:: System Configuration"

systemctl enable podman.socket
systemctl enable brew-setup.service 2>/dev/null || true
systemctl enable brew-update.timer 2>/dev/null || true
systemctl enable brew-upgrade.timer 2>/dev/null || true

echo "::endgroup::"

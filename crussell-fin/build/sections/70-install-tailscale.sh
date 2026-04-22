#!/usr/bin/env bash

set -eoux pipefail

echo "::group:: Install Tailscale"

dnf5 config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
dnf5 -y install --enablerepo='tailscale-stable' tailscale
dnf5 config-manager setopt tailscale-stable.enabled=0

echo "::endgroup::"

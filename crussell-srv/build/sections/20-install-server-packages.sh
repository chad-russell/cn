#!/usr/bin/env bash

set -eoux pipefail

echo "::group:: Install Server Packages"

# Core server utilities (not already in base image)
# Note: htop, jq, unzip, zip, rsync, tmux, tree, wget, curl, smartmontools, nvme-cli, nfs-utils, cifs-utils are in base
# Note: eza not available in Fedora 43, install via brew if needed
dnf5 install -y \
    podman-compose \
    restic \
    btop \
    iotop \
    ncdu \
    du-dust \
    ripgrep \
    fd-find \
    bat \
    yq \
    git \
    neovim \
    helix \
    lm_sensors \
    hdparm

echo "::endgroup::"

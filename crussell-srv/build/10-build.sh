#!/usr/bin/env bash

set -eoux pipefail

###############################################################################
# Server Build Script
###############################################################################

# Source helper functions
# shellcheck source=/dev/null
source /ctx/build/copr-helpers.sh

echo "::group:: Copy Custom Files"

cp -a /ctx/oci/brew/. /

# Copy default user configs to skel
cp -a /ctx/custom/skel/. /etc/skel/

# Copy Brewfiles to standard location
mkdir -p /usr/share/ublue-os/homebrew/
cp /ctx/custom/brew/*.Brewfile /usr/share/ublue-os/homebrew/ 2>/dev/null || true

# Consolidate Just Files
mkdir -p /usr/share/ublue-os/just/
find /ctx/custom/ujust -iname '*.just' -exec printf "\n\n" \; -exec cat {} \; >> /usr/share/ublue-os/just/60-custom.just

echo "::endgroup::"

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
    hdparm \
    syncthing

echo "::endgroup::"

echo "::group:: Install Tailscale"

dnf5 config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
dnf5 -y install --enablerepo='tailscale-stable' tailscale
dnf5 config-manager setopt tailscale-stable.enabled=0

mkdir -p /usr/share/ublue-os/privileged-setup.hooks.d/
cp /ctx/build/tailscale/10-tailscale.sh /usr/share/ublue-os/privileged-setup.hooks.d/ 2>/dev/null || true

echo "::endgroup::"

echo "::group:: Configure Zsh as Default Shell"

dnf5 install -y zsh 2>/dev/null || true

ZSH_PATH=$(which zsh)

if ! grep -qxF "$ZSH_PATH" /etc/shells; then
    echo "$ZSH_PATH" >> /etc/shells
fi

sed -i "s|SHELL=/bin/bash|SHELL=$ZSH_PATH|g" /etc/default/useradd

cp /ctx/build/zsh/skel-zshrc /etc/skel/.zshrc

echo "::endgroup::"

echo "::group:: System Configuration"

# Enable podman socket for API access
systemctl enable podman.socket

# Enable brew services (if using homebrew)
systemctl enable brew-setup.service 2>/dev/null || true
systemctl enable brew-update.timer 2>/dev/null || true
systemctl enable brew-upgrade.timer 2>/dev/null || true

# Enable tailscale
systemctl enable tailscaled.service

# Enable syncthing for user (will be started by user later)
# systemctl enable syncthing@.service is a template, user enables per-user

echo "::endgroup::"

echo "::group:: Server Hardening (Optional)"

# Set reasonable defaults for headless operation
# Disable root login via SSH (default on Fedora)
# Ensure firewall is available
dnf5 install -y firewalld 2>/dev/null || true
systemctl enable firewalld

echo "::endgroup::"

echo "Server build complete!"

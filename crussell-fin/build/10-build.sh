#!/usr/bin/env bash

set -eoux pipefail

###############################################################################
# Main Build Script
###############################################################################
# This script follows the @ublue-os/bluefin pattern for build scripts.
# It uses set -eoux pipefail for strict error handling and debugging.
###############################################################################

# Source helper functions
# shellcheck source=/dev/null
source /ctx/build/copr-helpers.sh

echo "::group:: Copy Custom Files"

cp -a /ctx/oci/common/shared/. /
cp -a /ctx/oci/common/bluefin/. /
cp -a /ctx/oci/brew/. /

# Copy default user configs to skel
cp -a /ctx/custom/skel/. /etc/skel/

# Copy Brewfiles to standard location
mkdir -p /usr/share/ublue-os/homebrew/
cp /ctx/custom/brew/*.Brewfile /usr/share/ublue-os/homebrew/

# Consolidate Just Files
mkdir -p /usr/share/ublue-os/just/
find /ctx/custom/ujust -iname '*.just' -exec printf "\n\n" \; -exec cat {} \; >> /usr/share/ublue-os/just/60-custom.just

# Copy Flatpak preinstall files
mkdir -p /etc/flatpak/preinstall.d/
cp /ctx/custom/flatpaks/*.preinstall /etc/flatpak/preinstall.d/

echo "::endgroup::"

echo "::group:: Custom MOTD"

cp /ctx/build/motd.sh /usr/bin/ublue-motd
chmod +x /usr/bin/ublue-motd

echo "::endgroup::"

echo "::group:: Install Packages"

# Install COSMIC alongside the Silverblue GNOME session so GDM can offer both.
# Fedora 43 ships current COSMIC packages directly in the main repositories.
dnf5 -y install \
    cosmic-session \
    cosmic-edit

# Install niri (scrollable-tiling Wayland compositor) from COPR
copr_install_isolated "yalter/niri" niri

# Install Ghostty terminal emulator from COPR
copr_install_isolated "scottames/ghostty" ghostty

# Install supporting packages used by the shell environment.
dnf5 -y install \
    wl-clipboard \
    cava

echo "::endgroup::"

echo "::group:: Niri Defaults"

mkdir -p /etc/xdg/niri
cp /usr/share/doc/niri/default-config.kdl /etc/xdg/niri/config.kdl

echo "::endgroup::"

echo "::group:: Install Supporting Utilities"

# Install utilities for niri and DMS
dnf5 install -y \
    fuzzel \
    swaybg \
    swaylock \
    mako \
    xdg-desktop-portal-gnome \
    xdg-desktop-portal-gtk \
    papirus-icon-theme \
    gcc \
    gcc-c++ \
    make \
    vulkan-loader \
    wtype

echo "::endgroup::"

echo "::group:: Install Vicinae"

# Install Vicinae launcher from COPR (requires cmark-gfm dependency COPR)
# Note: copr_install_isolated doesn't handle dependent COPRs, so we do it manually
echo "Installing Vicinae and cmark-gfm dependency..."
dnf5 -y copr enable quadratech188/cmark-gfm
dnf5 -y copr enable quadratech188/vicinae
dnf5 -y install --enablerepo=copr:copr.fedorainfracloud.org:quadratech188:cmark-gfm --enablerepo=copr:copr.fedorainfracloud.org:quadratech188:vicinae vicinae
dnf5 -y copr disable quadratech188/vicinae
dnf5 -y copr disable quadratech188/cmark-gfm

echo "::endgroup::"

echo "::group:: Install Tailscale"

# Install Tailscale from official repository (following Bluefin pattern)
# Add the Tailscale repository
dnf5 config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo

# Install Tailscale (repo auto-enables for this install only)
dnf5 -y install --enablerepo='tailscale-stable' tailscale

# Disable the repository to prevent it from persisting in the image
dnf5 config-manager setopt tailscale-stable.enabled=0

# Copy privileged setup hook for automatic user configuration
mkdir -p /usr/share/ublue-os/privileged-setup.hooks.d/
cp /ctx/build/tailscale/10-tailscale.sh /usr/share/ublue-os/privileged-setup.hooks.d/
chmod +x /usr/share/ublue-os/privileged-setup.hooks.d/10-tailscale.sh

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

echo "::group:: Install Noctalia Shell"

# Add Terra repository for the current Fedora release.
# Fyralabs no longer publishes a shared terra-release.repo file, so define the
# repo directly against the versioned baseurl.
FEDORA_VERSION=$(rpm -E %fedora)

cat > /etc/yum.repos.d/terra.repo <<EOF
[terra]
name=Terra ${FEDORA_VERSION}
baseurl=https://repos.fyralabs.com/terra${FEDORA_VERSION}/
enabled=0
gpgcheck=1
gpgkey=https://repos.fyralabs.com/terra${FEDORA_VERSION}/key.asc
EOF

# Install noctalia-shell and Terra-hosted companion packages.
dnf5 install -y --enablerepo=terra \
    noctalia-shell \
    cliphist \
    matugen

# Disable the repository to prevent accidental updates
dnf5 config-manager setopt terra.enabled=0

echo "::endgroup::"

echo "Custom build complete!"

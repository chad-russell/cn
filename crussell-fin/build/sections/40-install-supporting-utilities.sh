#!/usr/bin/env bash

set -eoux pipefail

echo "::group:: Install Supporting Utilities"

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

#!/usr/bin/env bash

set -eoux pipefail

echo "::group:: Niri Defaults"

mkdir -p /etc/xdg/niri
cp /usr/share/doc/niri/default-config.kdl /etc/xdg/niri/config.kdl

echo "::endgroup::"

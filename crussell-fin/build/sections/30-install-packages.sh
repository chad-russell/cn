#!/usr/bin/env bash

set -eoux pipefail

# shellcheck source=/dev/null
source /ctx/build/copr-helpers.sh

echo "::group:: Install Packages"

copr_install_isolated "yalter/niri" niri
copr_install_isolated "scottames/ghostty" ghostty

dnf5 -y install \
    wl-clipboard \
    cava

echo "::endgroup::"

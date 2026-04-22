#!/usr/bin/env bash

set -eoux pipefail

scripts=(
    /ctx/build/sections/10-copy-custom-files.sh
    /ctx/build/sections/20-custom-motd.sh
    /ctx/build/sections/30-install-packages.sh
    /ctx/build/sections/40-niri-defaults.sh
    /ctx/build/sections/50-install-supporting-utilities.sh
    /ctx/build/sections/60-install-vicinae.sh
    /ctx/build/sections/70-install-tailscale.sh
    /ctx/build/sections/80-configure-zsh-default-shell.sh
    /ctx/build/sections/90-install-noctalia-shell.sh
)

for script in "${scripts[@]}"; do
    bash "$script"
done

echo "Custom build complete!"

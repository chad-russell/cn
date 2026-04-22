#!/usr/bin/env bash

set -eoux pipefail

scripts=(
    /ctx/build/sections/10-copy-custom-files.sh
    /ctx/build/sections/20-install-server-packages.sh
    /ctx/build/sections/30-install-tailscale.sh
    /ctx/build/sections/40-configure-zsh-default-shell.sh
    /ctx/build/sections/50-system-configuration.sh
    /ctx/build/sections/60-server-hardening.sh
)

for script in "${scripts[@]}"; do
    bash "$script"
done

echo "Server build complete!"

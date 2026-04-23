#!/usr/bin/env bash

set -eoux pipefail

echo "::group:: Configure Zsh as Default Shell"

dnf5 install -y zsh 2>/dev/null || true

ZSH_PATH=$(which zsh)

if ! grep -qxF "$ZSH_PATH" /etc/shells; then
    echo "$ZSH_PATH" >> /etc/shells
fi

sed -i "s|SHELL=/bin/bash|SHELL=$ZSH_PATH|g" /etc/default/useradd

echo "::endgroup::"

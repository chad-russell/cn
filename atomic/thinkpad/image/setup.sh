#!/usr/bin/env bash
# One-shot FIRST-TIME setup: build the image and adopt it as the boot image.
# Equivalent to: ./build.sh && ./switch.sh
#
# Run this once when first moving the host onto the custom image (or when
# re-pointing at a different image/tag). For every subsequent Containerfile
# change, the loop is instead: ./build.sh && ./upgrade.sh
# (See switch.sh vs upgrade.sh — switch is for the reference, upgrade for content.)
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [1/2] build"
"${SELF_DIR}/build.sh"

echo
echo "==> [2/2] switch (one-time adopt)"
"${SELF_DIR}/switch.sh"

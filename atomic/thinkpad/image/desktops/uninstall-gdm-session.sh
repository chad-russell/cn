#!/usr/bin/env bash
set -euo pipefail

sudo rm -f /usr/local/bin/niri-bwrap-session
sudo rm -f /usr/local/share/wayland-sessions/niri-bwrap.desktop

echo 'Removed /usr/local GDM session entry and launcher.'

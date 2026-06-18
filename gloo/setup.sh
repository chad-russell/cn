#!/usr/bin/env bash
# One-shot setup for the local Gloo dev workflow on the thinkpad.
#   1. enable the rootless podman socket (so the agent container can drive
#      sibling containers)
#   2. relabel ~/Gloo so containers can access it under SELinux
#   3. install podman-compose (native libpod compose provider) and pin it
#
# Run on the host (or in the dev toolbox — ~/.pi and ~/Gloo are shared, and
# systemctl --user / sudo reach the host). Re-runnable / idempotent.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLOO_DIR="$HOME/Gloo"

echo "==> [1/3] Enabling rootless podman socket"
systemctl --user enable --now podman.socket
systemctl --user is-active podman.socket && echo "    socket active"

echo
echo "==> [2/3] Relabeling $GLOO_DIR for container access (SELinux)"
# Fedora enforces SELinux. Bind-mounted host files default to user_home_t,
# which containers can't read; and `:Z` mounts lock files to ONE container's
# MCS category, blocking all others. Labeling ~/Gloo as container_file_t:s0
# (no categories) lets EVERY container read/write it, persistently. New files
# created under it inherit the label, so future clones are covered.
if [ -d "$GLOO_DIR" ]; then
  sudo semanage fcontext -a -t container_file_t "$GLOO_DIR(/.*)?" 2>/dev/null \
    || sudo semanage fcontext -m -t container_file_t "$GLOO_DIR(/.*)?"
  sudo restorecon -R "$GLOO_DIR"
  echo "    $(ls -dZ "$GLOO_DIR" | awk '{print $1}')  (should be ...:container_file_t:s0)"
else
  echo "    $GLOO_DIR doesn't exist yet — create it and re-run this step:"
  echo "      sudo semanage fcontext -a -t container_file_t \"$GLOO_DIR(/.*)?\" && sudo restorecon -R \"$GLOO_DIR\""
fi

echo
echo "==> [3/3] Installing native compose provider (podman-compose)"
# Podman does not bundle `podman compose`. The default external provider is
# docker-compose, which talks to podman's Docker-compat REST shim — containers
# it creates CANNOT be exec'd/healthchecked by rootless podman (conmon returns
# empty, healthchecks falsely fail, `app` never starts). podman-compose drives
# the native libpod API instead, so exec + healthchecks + `podman compose` all
# work. Install it user-scoped (~/.local/bin, no root) and pin it as provider.
if command -v podman-compose >/dev/null 2>&1; then
  echo "    podman-compose already installed: $(command -v podman-compose)"
else
  echo "    bootstrapping pip (ensurepip --user) and installing podman-compose"
  python3 -m ensurepip --user >/dev/null 2>&1 || true
  python3 -m pip install --user --quiet podman-compose
fi
# Pin it in containers.conf so `podman compose` is deterministic and never
# silently falls back to docker-compose.
CC="$HOME/.config/containers/containers.conf"
mkdir -p "$(dirname "$CC")"
touch "$CC"
PC="$(command -v podman-compose 2>/dev/null || echo "$HOME/.local/bin/podman-compose")"
if ! grep -qE "^compose_providers" "$CC"; then
  if grep -qE "^\[engine\]" "$CC"; then
    sed -i "/^\[engine\]/a compose_providers = [\"$PC\"]" "$CC"
  else
    printf '\n[engine]\ncompose_providers = ["%s"]\n' "$PC" >> "$CC"
  fi
  echo "    pinned compose_providers = [\"$PC\"] in $CC"
else
  echo "    compose_providers already set in $CC"
fi
# Defensive: warn if docker-compose (Podman Desktop leftover) is still present.
if [ -x /usr/local/bin/docker-compose ]; then
  echo "    WARNING: /usr/local/bin/docker-compose still present (Podman Desktop"
  echo "    leftover). It creates containers rootless podman can't exec. Remove it:"
  echo "      sudo rm -f /usr/local/bin/docker-compose"
fi

echo
# sanity-check: confirm `podman compose` resolves to podman-compose
COMPOSE_VER="$(podman compose version 2>/dev/null | head -1 || true)"
[ -n "$COMPOSE_VER" ] && echo "    podman compose -> $COMPOSE_VER"

echo
echo "Done. Next:"
echo "  1. (once) rebuild the dev-shell image so the agent has podman:"
echo "       cd ~/Code/cn/atomic/thinkpad/toolbox && ./build.sh"
echo "  2. fetch a project's .env.local from bee:"
echo "       ~/Code/cn/gloo/fetch-env.sh polymer"
echo "  3. bring up a project + run pi:"
echo "       ~/Code/cn/gloo/dev polymer up"
echo "       ~/Code/cn/gloo/dev polymer pi"

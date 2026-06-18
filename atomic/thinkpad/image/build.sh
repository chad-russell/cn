#!/usr/bin/env bash
# Build the custom Silverblue image.
#
# IMPORTANT: runs podman as ROOT (sudo). The image must land in root's
# containers-storage (/var/lib/containers/storage) because `bootc switch
# --transport containers-storage` reads from there. A rootless build would put
# the image in your user storage, which bootc cannot see.
#
# Output:
#   localhost/silverblue-thinkpad:<FEDORA_MAJOR_VERSION>            (rolling; what switch.sh targets)
#   localhost/silverblue-thinkpad:<FEDORA_MAJOR_VERSION>-<sha>-<ts> (immutable; per-build, for history)
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- config (keep in sync with switch.sh) -----------------------------
FEDORA_MAJOR_VERSION="44"
IMAGE="localhost/silverblue-thinkpad:${FEDORA_MAJOR_VERSION}"

# ---- per-build version (lets `bootc upgrade` detect a rebuild) ----------
# A unique IMAGE_VERSION is injected into the image as an OCI LABEL + /usr file
# (see Containerfile step 3). The LABEL lives in the image config, so it changes
# the image's manifest/config digest on every build — and that digest is what
# `bootc upgrade` compares against the booted image. So after the one-time
# `switch.sh`, every `./build.sh && ./upgrade.sh` deploys the new build instead
# of no-op'ing. Falls back to "nogit" outside a git checkout; the UTC timestamp
# alone still guarantees uniqueness.
if git -C "${SELF_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_SHA="$(git -C "${SELF_DIR}" rev-parse --short HEAD)"
else
  GIT_SHA="nogit"
fi
IMAGE_VERSION="${FEDORA_MAJOR_VERSION}-${GIT_SHA}-$(date -u +%Y%m%d-%H%M%S)"
# Immutable per-build tag (build history / `podman images` inspection). The
# rolling "${IMAGE}" tag is what upgrade.sh / switch.sh point at.
VERSION_TAG="localhost/silverblue-thinkpad:${IMAGE_VERSION}"

echo "==> Building ${IMAGE}  (version ${IMAGE_VERSION})"
# --pull=newer: refresh the base if a newer 44.x exists (gets Fedora updates
# baked in); still works on first build when the base isn't cached yet.
sudo podman build \
  --pull=newer \
  --build-arg "IMAGE_VERSION=${IMAGE_VERSION}" \
  -t "${IMAGE}" \
  -t "${VERSION_TAG}" \
  -f "${SELF_DIR}/Containerfile" \
  "${SELF_DIR}"

echo
echo "Done. Images are in root's podman storage:"
echo "  sudo podman images localhost/silverblue-thinkpad"
echo
echo "Switch the host onto it (bootc):"
echo "  ./switch.sh      # then: systemctl reboot"

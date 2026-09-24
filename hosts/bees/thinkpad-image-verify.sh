#!/usr/bin/env bash
# thinkpad-image-verify — post-build gates for the thinkpad host image.
#
# Shared by BOTH paths that build this image, so they can never drift:
#   - bees thinkpad-image-build.service (nightly publish — calls the
#     /etc-deployed copy BEFORE pushing anything to zot)
#   - the ci.yml `thinkpad-image` PR job (calls this from the PR checkout,
#     so a PR is gated by its OWN version of these checks)
#
# What it asserts on a mounted image (fail = non-zero before publish/merge):
#   1. baked /etc/hosts — COPY is the one Containerfile step whose failure
#      is silent (RUN would be runtime-masked), so grep the layer itself.
#   2. wayland sessions — niri present; cosmic/hyprland absent (soft-removed
#      / removed — a stray COPR line would resurrect them).
#   3. niri-caelestia-shell artifacts — a silent CMake/install failure
#      must not ship an image whose shell is missing at next login.
#
# Usage: thinkpad-image-verify.sh <image-ref>
# Runs wherever podman can see the image; for the dedicated btrfs build
# store, the caller sets CONTAINERS_STORAGE_CONF (both callers do).
set -euo pipefail

IMAGE="${1:?usage: thinkpad-image-verify.sh <image-ref>}"

VERIFY_MNT="$(podman image mount "${IMAGE}")" || {
  echo "ERROR: cannot mount ${IMAGE} for verification" >&2
  exit 1
}
trap 'podman image unmount "${IMAGE}" >/dev/null 2>&1 || true' EXIT

# ---- gate 1: baked /etc/hosts -------------------------------------------
echo "==> verifying baked /etc/hosts in ${IMAGE}"
if ! grep -q 'Nebula overlay hosts' "${VERIFY_MNT}/etc/hosts" \
   || ! grep -Eq '^10\.10\.0\.6[[:space:]]+bees' "${VERIFY_MNT}/etc/hosts"; then
  echo "ERROR: /etc/hosts in ${IMAGE} lacks the Nebula overlay entries" >&2
  echo "  Containerfile step 3.7 (COPY etc-hosts /etc/hosts) did not land" >&2
  exit 1
fi
echo "    /etc/hosts entries verified in image layer"

# ---- gate 2: wayland sessions -------------------------------------------
echo "==> verifying wayland sessions in ${IMAGE}"
for session in niri; do
  if [ ! -f "${VERIFY_MNT}/usr/share/wayland-sessions/${session}.desktop" ]; then
    echo "ERROR: ${session}.desktop missing from ${IMAGE}" >&2
    echo "  expected sessions: niri (GNOME ships in the base image)" >&2
    exit 1
  fi
done
if [ -f "${VERIFY_MNT}/usr/share/wayland-sessions/cosmic.desktop" ]; then
  echo "ERROR: cosmic.desktop present but COSMIC is soft-removed" >&2
  echo "  un-comment the cosmic lines in the Containerfile or drop this check" >&2
  exit 1
fi
if [ -f "${VERIFY_MNT}/usr/share/wayland-sessions/hyprland.desktop" ]; then
  echo "ERROR: hyprland.desktop present but Hyprland was removed 2026-09-02" >&2
  echo "  the mineiro/hyprland COPR line should be gone from the Containerfile" >&2
  exit 1
fi
echo "    wayland sessions verified: niri (+ GNOME from base)"

# ---- gate 3: niri-caelestia-shell fork artifacts -------------------------
echo "==> verifying niri-caelestia-shell artifacts in ${IMAGE}"
for artifact in \
  "${VERIFY_MNT}/usr/lib64/qt6/qml/Caelestia/qmldir" \
  "${VERIFY_MNT}/usr/lib64/qt6/qml/Caelestia/Internal/qmldir" \
  "${VERIFY_MNT}/usr/lib64/qt6/qml/Caelestia/Services/qmldir" \
  "${VERIFY_MNT}/usr/lib/caelestia/version" \
  "${VERIFY_MNT}/etc/xdg/quickshell/niri-caelestia-shell/shell.qml"
do
  if [ ! -f "${artifact}" ]; then
    echo "ERROR: ${artifact} missing from ${IMAGE}" >&2
    echo "  the niri-caelestia-shell build (Containerfile step 2.5) did not land" >&2
    exit 1
  fi
done
echo "    niri-caelestia-shell artifacts verified"

echo "==> thinkpad-image-verify: all gates passed for ${IMAGE}"

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
#   2. wayland sessions — niri + hyprland + mango present (compositor trial
#      stack, 2026-11; was: niri only / hyprland rejected), cosmic absent.
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
# niri (primary) + the two 2026-11 compositor-trial sessions. Trial runbook:
# hosts/thinkpad/hyprland/README.md. When the trial concludes, keep only the
# winner's line here and drop the loser's install block in the Containerfile.
for session in niri hyprland; do
  if [ ! -f "${VERIFY_MNT}/usr/share/wayland-sessions/${session}.desktop" ]; then
    echo "ERROR: ${session}.desktop missing from ${IMAGE}" >&2
    echo "  expected sessions: niri + hyprland (GNOME ships in the base image)" >&2
    exit 1
  fi
done
# mango's session file name is not asserted exactly (upstream doesn't pin it
# in docs) — match any *mango* session file instead.
if ! ls "${VERIFY_MNT}/usr/share/wayland-sessions/" 2>/dev/null | grep -qi mango; then
  echo "ERROR: no mango session file in ${IMAGE}" >&2
  echo "  Containerfile step 2.7 (Terra/mangowm) did not land" >&2
  exit 1
fi
if [ -f "${VERIFY_MNT}/usr/share/wayland-sessions/cosmic.desktop" ]; then
  echo "ERROR: cosmic.desktop present but COSMIC is soft-removed" >&2
  echo "  un-comment the cosmic lines in the Containerfile or drop this check" >&2
  exit 1
fi
echo "    wayland sessions verified: niri + hyprland + mango (+ GNOME from base)"

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

# ---- gate 4: baked system services (Containerfile step 3.9) --------------
# COPY is silent on failure (same rationale as gate 1): assert the system
# layer landed — quadlets, timers, the ntfy template, the sshd drop-in, the
# linger tmpfiles, and the nebula boot-enablement symlink.
echo "==> verifying baked system services in ${IMAGE}"
for artifact in \
  "${VERIFY_MNT}/usr/share/containers/systemd/nebula.container" \
  "${VERIFY_MNT}/usr/share/containers/systemd/tailscale.container" \
  "${VERIFY_MNT}/usr/share/containers/systemd/restic-backup.container" \
  "${VERIFY_MNT}/usr/share/containers/systemd/restic-check.container" \
  "${VERIFY_MNT}/usr/lib/systemd/system/restic-backup.timer" \
  "${VERIFY_MNT}/usr/lib/systemd/system/restic-check.timer" \
  "${VERIFY_MNT}/usr/lib/systemd/system/restic-ntfy-failure@.service" \
  "${VERIFY_MNT}/etc/ssh/sshd_config.d/10-key-only.conf" \
  "${VERIFY_MNT}/usr/lib/tmpfiles.d/thinkpad-linger.conf"; do
  if [ ! -f "${artifact}" ]; then
    echo "ERROR: ${artifact} missing from ${IMAGE}" >&2
    echo "  Containerfile step 3.9 (baked system services) did not land" >&2
    exit 1
  fi
done
# nebula enablement: wants symlink to the generator output (quadlet units are
# generated at boot, so enablement can only be a symlink).
NEBULA_WANT="${VERIFY_MNT}/etc/systemd/system/multi-user.target.wants/nebula.service"
if [ ! -L "${NEBULA_WANT}" ] \
   || [ "$(readlink "${NEBULA_WANT}")" != "/run/systemd/generator/nebula.service" ]; then
  echo "ERROR: ${NEBULA_WANT} missing or not pointing at the generator output" >&2
  exit 1
fi
# restic timers + sshd enabled at build time (systemctl enable in the build).
# Where enablement symlinks land depends on the base layout (/etc → usr/etc
# symlink vs real dir) — accept either.
want_exists() { # <unit> <dir-under-systemd>
  local base
  for base in "${VERIFY_MNT}/usr/etc/systemd/system" "${VERIFY_MNT}/etc/systemd/system"; do
    [ -e "${base}/${1}" ] || [ -L "${base}/${1}" ] && return 0
  done
  return 1
}
want_exists "timers.target.wants/restic-backup.timer" \
  || { echo "ERROR: restic-backup.timer not enabled in ${IMAGE}" >&2; exit 1; }
want_exists "timers.target.wants/restic-check.timer" \
  || { echo "ERROR: restic-check.timer not enabled in ${IMAGE}" >&2; exit 1; }
want_exists "multi-user.target.wants/sshd.service" \
  || { echo "ERROR: sshd.service not enabled in ${IMAGE}" >&2; exit 1; }
echo "    baked system services verified (quadlets, timers, sshd, linger)"

echo "==> thinkpad-image-verify: all gates passed for ${IMAGE}"

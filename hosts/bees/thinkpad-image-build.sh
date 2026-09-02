#!/usr/bin/env bash
# Build + publish the thinkpad host image to the local zot registry.
#
# Runs ON BEES as thinkpad-image-build.service (system unit, root). Pulls the
# cn repo, builds hosts/thinkpad/host-image/Containerfile with root podman
# (--pull=newer so Fedora base/dnf updates ride along even without repo
# changes), and pushes to zot as:
#   10.10.0.6:5000/cn/thinkpad-host:44            (rolling — what think boots)
#   10.10.0.6:5000/cn/thinkpad-host:44-<sha>-<ts> (immutable history; zot
#                                                  retention keeps last 3)
#
# The rolling :44 always exists (pushed first), so a crash mid-publish can
# never leave think's bootc reference dangling.
#
# Triggered daily by thinkpad-image-build.timer (~05:10 America/New_York,
# after the 05:00 restic backup window) or manually with
#   sudo systemctl start thinkpad-image-build.service
set -euo pipefail

REPO=/home/crussell/Code/cn
FEDORA_MAJOR_VERSION="44"
REGISTRY="10.10.0.6:5000"
IMAGE="${REGISTRY}/cn/thinkpad-host:${FEDORA_MAJOR_VERSION}"

# ---- repo sync (ff-only; the build must reflect a real origin/main state) --
# git runs AS crussell (repo owner) via runuser: root's git would trip
# "dubious ownership" on the crussell-owned repo, and a root `reset --hard`
# would leave root-owned files in the tree (breaking later crussell pulls).
cd "${REPO}"
git_as() { runuser -u crussell -- git -C "${REPO}" "$@"; }
if ! git_as diff --quiet || ! git_as diff --cached --quiet; then
  echo "ERROR: ${REPO} has uncommitted changes — commit/stash first." >&2
  exit 1
fi
git_as fetch origin
git_as reset --hard origin/main
echo "==> building from $(git_as rev-parse --short HEAD) $(git_as log -1 --format=%cd --date=short)"

# ---- version stamp: sha + UTC timestamp (unique per build, same scheme as
# the thinkpad-local build.sh; --dirty flag if the tree wasn't clean — cannot
# happen after the reset above, kept as a belt-and-suspenders guard)
GIT_SHA="$(git_as rev-parse --short HEAD)"
if ! git_as diff --quiet; then GIT_SHA="${GIT_SHA}-dirty"; fi
IMAGE_VERSION="${FEDORA_MAJOR_VERSION}-${GIT_SHA}-$(date -u +%Y%m%d-%H%M%S)"
VERSION_TAG="${REGISTRY}/cn/thinkpad-host:${IMAGE_VERSION}"

# ---- build (root podman; cache mounts keep dnf layers warm across runs) ---
echo "==> podman build ${IMAGE}  (version ${IMAGE_VERSION})"
podman build \
  --pull=newer \
  --build-arg "IMAGE_VERSION=${IMAGE_VERSION}" \
  -t "${IMAGE}" \
  -t "${VERSION_TAG}" \
  -f "${REPO}/hosts/thinkpad/host-image/Containerfile" \
  "${REPO}/hosts/thinkpad/host-image"

# ---- publish: rolling tag first (never dangles), then the immutable tag ----
# zot is an insecure (plain-HTTP, Nebula-only) registry from podman's POV:
# --tls-verify=false is correct here, not a security hole — transport security
# is the Nebula tunnel.
echo "==> push ${IMAGE}"
podman push --tls-verify=false "${IMAGE}"
echo "==> push ${VERSION_TAG}"
podman push --tls-verify=false "${VERSION_TAG}"

# ---- post-build gate: the baked /etc/hosts MUST be in the published image ----
# COPY of /etc/hosts is the one step whose failure mode is silent (a runtime
# mask would no-op it), so verify the artifact itself: mount the built image
# and grep its actual layer content. Fails the build loudly instead of
# publishing a hosts-less image.
echo "==> verifying baked /etc/hosts in the built image"
VERIFY_MNT="$(podman image mount "${IMAGE}")" || {
  echo "ERROR: cannot mount ${IMAGE} for hosts verification" >&2; exit 1; }
if ! grep -q 'Nebula overlay hosts' "${VERIFY_MNT}/etc/hosts" \
   || ! grep -Eq '^10\.10\.0\.6[[:space:]]+bees' "${VERIFY_MNT}/etc/hosts"; then
  echo "ERROR: /etc/hosts in ${IMAGE} lacks the Nebula overlay entries" >&2
  echo "  Containerfile step 3.7 (COPY etc-hosts /etc/hosts) did not land" >&2
  podman image unmount "${IMAGE}" >/dev/null 2>&1 || true
  exit 1
fi
echo "    /etc/hosts entries verified in image layer"

# ---- post-build gate: session .desktop files must match the intended set ---
# The GDM session list is the user-visible surface of this image; a missing
# COPR or a fat-fingered package name would silently drop a session. Assert
# the expected files exist in the layer (COSMIC is soft-removed — its absence
# is expected until re-enabled). Same mounted image, so this rides the mount
# already held open above.
echo "==> verifying wayland sessions in the built image"
for session in niri; do
  if [ ! -f "${VERIFY_MNT}/usr/share/wayland-sessions/${session}.desktop" ]; then
    echo "ERROR: ${session}.desktop missing from ${IMAGE}" >&2
    echo "  expected sessions: niri (GNOME ships in the base image)" >&2
    podman image unmount "${IMAGE}" >/dev/null 2>&1 || true
    exit 1
  fi
done
echo "    wayland sessions verified: niri (+ GNOME from base)"
if [ -f "${VERIFY_MNT}/usr/share/wayland-sessions/cosmic.desktop" ]; then
  echo "ERROR: cosmic.desktop present but COSMIC is soft-removed" >&2
  echo "  un-comment the cosmic lines in the Containerfile or drop this check" >&2
  podman image unmount "${IMAGE}" >/dev/null 2>&1 || true
  exit 1
fi
if [ -f "${VERIFY_MNT}/usr/share/wayland-sessions/hyprland.desktop" ]; then
  echo "ERROR: hyprland.desktop present but Hyprland was removed 2026-09-02" >&2
  echo "  the mineiro/hyprland COPR line should be gone from the Containerfile" >&2
  podman image unmount "${IMAGE}" >/dev/null 2>&1 || true
  exit 1
fi

# ---- post-build gate: niri-caelestia-shell fork artifacts -------------------
# Containerfile step 2.5 installs the fork system-wide; assert the load-bearing
# artifacts landed so a silent CMake/install failure can't publish an image
# whose shell is missing at next login.
echo "==> verifying niri-caelestia-shell artifacts in the built image"
for artifact in \
  "${VERIFY_MNT}/usr/lib/qt6/qml/Caelestia/qmldir" \
  "${VERIFY_MNT}/usr/lib/qt6/qml/Caelestia/Internal/qmldir" \
  "${VERIFY_MNT}/usr/lib/qt6/qml/Caelestia/Services/qmldir" \
  "${VERIFY_MNT}/usr/lib/caelestia/version" \
  "${VERIFY_MNT}/etc/xdg/quickshell/caelestia/shell.qml"
do
  if [ ! -f "${artifact}" ]; then
    echo "ERROR: ${artifact} missing from ${IMAGE}" >&2
    echo "  the niri-caelestia-shell build (Containerfile step 2.5) did not land" >&2
    podman image unmount "${IMAGE}" >/dev/null 2>&1 || true
    exit 1
  fi
done
echo "    niri-caelestia-shell artifacts verified"
podman image unmount "${IMAGE}" >/dev/null 2>&1 || true

# ---- local housekeeping: drop the build-only copies (registry is the store)
echo "==> pruning local build images"
podman rmi "${IMAGE}" "${VERSION_TAG}" >/dev/null 2>&1 || true

echo
echo "==> published ${IMAGE_VERSION}"
echo "    registry: http://${REGISTRY}/v2/_catalog"

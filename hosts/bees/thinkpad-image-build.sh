#!/usr/bin/env bash
# Build + publish the thinkpad host image to the local zot registry.
#
# Runs ON BEES as thinkpad-image-build.service (system unit, root). Pulls the
# cn repo, builds hosts/thinkpad/host-image/Containerfile with root podman
# (--pull=newer so Fedora base/dnf updates ride along even without repo
# changes), and pushes to zot as:
#   10.10.0.6:5000/cn/thinkpad-host:stable             (rolling — version-
#   10.10.0.6:5000/cn/thinkpad-host:<fedora>-<sha>-<ts> neutral; what think
#                                                       boots; zot keeps it)
#   (immutable history; zot retention keeps the last 3, any version)
#
# The rolling :stable is version-neutral ON PURPOSE: a Fedora major bump
# changes only hosts/thinkpad/host-image/version (the single source, sourced
# below) — never the boot reference or the zot retention patterns. (The old
# scheme rolling on :44 with retention anchored to ^44$ would have GC'd every
# version-45 tag within a day of a bump.)
#
# The rolling :stable always exists (pushed first), so a crash mid-publish can
# never leave think's bootc reference dangling.
#
# Triggered daily by thinkpad-image-build.timer (~05:10 America/New_York,
# after the 05:00 restic backup window) or manually with
#   sudo systemctl start thinkpad-image-build.service
set -euo pipefail

REPO=/home/crussell/Code/cn
REGISTRY="10.10.0.6:5000"
IMAGE="${REGISTRY}/cn/thinkpad-host:stable"

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

# FEDORA_MAJOR_VERSION, single source — sourced AFTER the sync above, which
# is what brings this file into existence on a checkout that predates it
# (the first post-fc86dc6 run failed exactly this way: line-28 source of a
# file the pre-merge checkout didn't have yet).
. "${REPO}/hosts/thinkpad/host-image/version"

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

# ---- verify BEFORE publish: a gate failure must never reach :stable ------
# Shared gates (hosts/session/shell artifacts) live in thinkpad-image-verify.sh
# — the same script the ci.yml PR job runs, so pre-merge and nightly can't
# drift. /etc copy is deployed from this same repo tree.
echo "==> verifying the built image (shared gates)"
/etc/thinkpad-image-verify.sh "${IMAGE}"

# ---- publish: rolling tag first (never dangles), then the immutable tag ----
# zot is an insecure (plain-HTTP, Nebula-only) registry from podman's POV:
# --tls-verify=false is correct here, not a security hole — transport security
# is the Nebula tunnel.
echo "==> push ${IMAGE}"
podman push --tls-verify=false "${IMAGE}"
echo "==> push ${VERSION_TAG}"
podman push --tls-verify=false "${VERSION_TAG}"

# ---- local housekeeping: drop the build-only copies (registry is the store)
echo "==> pruning local build images"
podman rmi "${IMAGE}" "${VERSION_TAG}" >/dev/null 2>&1 || true

echo
echo "==> published ${IMAGE_VERSION}"
echo "    registry: http://${REGISTRY}/v2/_catalog"

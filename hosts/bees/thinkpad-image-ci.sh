#!/usr/bin/env bash
# thinkpad-image-ci — build-once / promote-on-merge for the thinkpad host image.
#
# Called by .forgejo/workflows/ci.yml (thinkpad-image job) on the bees
# `nix-host` runner, from the repo checkout:
#
#   thinkpad-image-ci.sh pr       (pull_request) build -> verify -> push
#                                 cn/thinkpad-host:ctx-<hash>
#   thinkpad-image-ci.sh promote  (push to main)  if ctx-<hash> exists and is
#                                 not older than :stable, RETAG it to :stable
#                                 + its immutable version tag (registry-side
#                                 manifest copy: no rebuild, no blob upload,
#                                 seconds). Otherwise fall back to the
#                                 nightly unit (build -> verify -> publish).
#
# WHY (2026-11): before this, a merge built the image three times (PR job,
# push-to-main job, then the nightly or `cjust image-rebuild`), and CI
# deleted both of its builds right after verifying them, so a merged change
# only reached the laptop after another full build. Now the image that
# passed review is the exact image that ships.
#
# THE KEY is the git tree hash of hosts/thinkpad/host-image/, the build
# context (Containerfile + everything it COPYs). Same context = same build
# input, so a PR built from refs/pull/N/merge is promotable after merge even
# when unrelated main commits landed in between. Any change to the context
# dir, or a squash that changes it, means a different key and a fresh build.
#
# STALENESS GUARD: the build pulls the base image and dnf repos at build
# time, so an old PR build could carry older packages than the current
# :stable (the nightly runs daily with --pull=newer). Promote only if the
# candidate's build stamp is >= :stable's; otherwise rebuild.
#
# Version stamps keep the nightly's parseable format
# <fedora>-<id>-<YYYYMMDD>-<HHMMSS> (thinkpad-image-update and the health
# check read the date part). CI builds use id = c<ctx7>; the nightly keeps
# the commit sha. Neither id may contain '-'.
set -euo pipefail

MODE="${1:?usage: thinkpad-image-ci.sh pr|promote}"
REGISTRY="10.10.0.6:5000"
REPO_NAME="cn/thinkpad-host"
CTX_DIR="hosts/thinkpad/host-image"
SUDO=/run/wrappers/bin/sudo # job PATH lacks the NixOS setuid wrappers
STORE_ENV=(env CONTAINERS_STORAGE_CONF=/etc/thinkpad-build-storage.conf)

CTX="$(git rev-parse "HEAD:${CTX_DIR}")"
CAND_TAG="ctx-${CTX:0:12}"
echo "==> build context ${CTX_DIR} tree ${CTX} -> tag ${CAND_TAG}"

# ---- registry helpers (OCI distribution API over Nebula; python3 for JSON,
# the runner has no jq/skopeo). Accept both OCI and docker v2 manifests.
ACCEPT="application/vnd.oci.image.manifest.v1+json,application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.v2+json,application/vnd.docker.distribution.manifest.list.v2+json"

# version label of <tag>, empty if the tag doesn't exist
version_of() {
  local tag="$1" manifest digest
  manifest="$(curl -fsS --max-time 20 -H "Accept: ${ACCEPT}" \
    "http://${REGISTRY}/v2/${REPO_NAME}/manifests/${tag}" 2>/dev/null)" || return 0
  digest="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["config"]["digest"])' <<<"$manifest")"
  curl -fsS --max-time 20 "http://${REGISTRY}/v2/${REPO_NAME}/blobs/${digest}" |
    python3 -c 'import json,sys; print(json.load(sys.stdin).get("config",{}).get("Labels",{}).get("org.opencontainers.image.version",""))'
}

# <stamp> -> sortable YYYYMMDDHHMMSS (the last two '-' fields)
stamp_key() { awk -F- '{print $(NF-1) $NF}' <<<"$1"; }

# copy the manifest of <src> to each <dst> tag, byte-for-byte; the blobs are
# already in the repo, so this is an instant retag.
retag() {
  local src="$1" tmp ctype
  shift
  tmp="$(mktemp)"
  ctype="$(curl -fsS --max-time 30 -H "Accept: ${ACCEPT}" -o "$tmp" -w '%{content_type}' \
    "http://${REGISTRY}/v2/${REPO_NAME}/manifests/${src}")"
  for dst in "$@"; do
    echo "==> retag ${src} -> ${dst}"
    curl -fsS --max-time 30 -X PUT -H "Content-Type: ${ctype}" --data-binary "@${tmp}" \
      "http://${REGISTRY}/v2/${REPO_NAME}/manifests/${dst}" >/dev/null
  done
  rm -f "$tmp"
}

case "$MODE" in
pr)
  # shellcheck source=/dev/null
  . "${CTX_DIR}/version"
  VERSION="${FEDORA_MAJOR_VERSION}-c${CTX:0:7}-$(date -u +%Y%m%d-%H%M%S)"
  LOCAL="cn-thinkpad-host:${CAND_TAG}"
  REMOTE="${REGISTRY}/${REPO_NAME}:${CAND_TAG}"
  trap '$SUDO "${STORE_ENV[@]}" podman rmi "$LOCAL" "$REMOTE" >/dev/null 2>&1 || true' EXIT

  echo "==> build ${LOCAL} (version ${VERSION})"
  $SUDO "${STORE_ENV[@]}" podman build --pull=newer \
    --build-arg "IMAGE_VERSION=${VERSION}" \
    -t "$LOCAL" -t "$REMOTE" \
    -f "${CTX_DIR}/Containerfile" "$CTX_DIR"

  echo "==> verify (shared gates with the nightly)"
  $SUDO "${STORE_ENV[@]}" bash hosts/bees/thinkpad-image-verify.sh "$LOCAL"

  # Push only AFTER the gates pass: a ctx-* tag in zot means "verified".
  echo "==> push ${REMOTE}"
  $SUDO "${STORE_ENV[@]}" podman push --tls-verify=false "$REMOTE"
  echo "==> candidate ${CAND_TAG} = ${VERSION} (promoted to :stable on merge)"
  ;;

promote)
  CAND_VER="$(version_of "$CAND_TAG")"
  STABLE_VER="$(version_of stable)"
  echo "==> candidate ${CAND_TAG}: ${CAND_VER:-<none>}"
  echo "==> current :stable:   ${STABLE_VER:-<none>}"

  if [ -n "$CAND_VER" ] &&
    { [ -z "$STABLE_VER" ] || [ "$(stamp_key "$CAND_VER")" -ge "$(stamp_key "$STABLE_VER")" ]; }; then
    # Immutable tag first, then :stable (rolling tag last = never points at
    # something without a history entry; same rule as the nightly).
    retag "$CAND_TAG" "$CAND_VER" stable
    echo "==> promoted ${CAND_VER} to :stable (no rebuild)"
  else
    if [ -z "$CAND_VER" ]; then
      echo "==> no verified candidate for this context (PR not built, or retention expired)"
    else
      echo "==> candidate is older than :stable (a nightly ran since): rebuilding fresh"
    fi
    # Fallback = the nightly's own code path (build -> verify -> publish).
    # --wait blocks until the oneshot finishes and returns its result.
    $SUDO systemctl start --wait thinkpad-image-build.service
  fi
  ;;

*)
  echo "unknown mode: ${MODE}" >&2
  exit 2
  ;;
esac

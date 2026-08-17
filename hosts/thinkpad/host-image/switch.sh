#!/usr/bin/env bash
# Adopt the bees-built registry image as the host's boot image — the ONE-TIME
# command to move the thinkpad onto registry-driven updates:
#
#   bootc switch --transport registry --insecure 10.10.0.6:5000/cn/thinkpad-host:44
#
# After this, `bootc upgrade` (cjust image-upgrade) re-resolves :44 from the
# registry over Nebula and pulls only changed layers. The local build.sh flow
# remains the break-glass path while bees or Nebula is down.
#
# Prereq: bees's thinkpad-image-build.service has run at least once (it runs
# daily at ~05:10, or trigger it: `cjust image-rebuild`). Verify the image is
# there first — this script checks.
#
# IMPORTANT — switch vs upgrade (unchanged semantics from the local flow):
#   `bootc switch` compares the image REFERENCE (transport + name + tag), NOT
#   the image content. It's for the first adopt (or re-pointing at a different
#   image/tag); routine content updates use ./upgrade.sh (`bootc upgrade`),
#   which compares the manifest DIGEST and detects every rebuild because every
#   build stamps a unique OCI label.
set -euo pipefail

FEDORA_MAJOR_VERSION="44"
REGISTRY="10.10.0.6:5000"
IMAGE="${REGISTRY}/cn/thinkpad-host:${FEDORA_MAJOR_VERSION}"

# Sanity: the image must exist in the registry (and Nebula must be up).
echo "==> checking ${IMAGE} in the registry ..."
curl -fsSL --max-time 10 "http://${REGISTRY}/v2/" >/dev/null || {
  echo "ERROR: cannot reach ${REGISTRY} — is Nebula up on this host?" >&2
  exit 1
}
curl -fsSL "http://${REGISTRY}/v2/cn/thinkpad-host/tags/list" \
  | grep -q "\"${FEDORA_MAJOR_VERSION}\"" || {
  echo "ERROR: tag :${FEDORA_MAJOR_VERSION} not in the registry yet." >&2
  echo "       Trigger a build first:  cjust image-rebuild   (or wait for the daily timer)" >&2
  exit 1
}

echo "==> bootc switch --transport registry --insecure ${IMAGE}"
sudo bootc switch --transport registry --insecure "${IMAGE}"

cat <<EOF

New deployment staged. It is NOT active until you reboot:

  systemctl reboot

After reboot, verify which build you're on:
  cat /usr/lib/host-image-thinkpad-version
  bootc status     # image reference should show registry transport

From now on, routine updates are:
  cjust image-upgrade      # pull :44 diff from bees + stage (reboot to apply)

If the new image is broken, the previous deployment is still there — roll back:
  bootc rollback     # then: systemctl reboot
EOF

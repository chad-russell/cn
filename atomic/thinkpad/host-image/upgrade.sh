#!/usr/bin/env bash
# Apply a freshly rebuilt image to the host — the ROUTINE "I rebuilt :44, now
# boot it" command. Uses `bootc upgrade`, NOT `switch`.
#
# WHY UPGRADE, NOT SWITCH:
#   `bootc switch` compares the image REFERENCE (transport + name + tag), not
#   the image content. Pointing it at the same `...:44` you're already booted
#   on is a no-op BY DESIGN — it prints "Image specification is unchanged"
#   even though you just rebuilt :44 with new content. `switch` is for changing
#   the reference (adopting the image the first time, or pointing at a different
#   tag/image); `bootc upgrade` is for applying NEW CONTENT of the SAME
#   reference.
#
#   `bootc upgrade` re-resolves :44 from local podman storage (no network) and
#   compares the image's MANIFEST/CONFIG DIGEST against what's booted. Because
#   build.sh stamps every image with a unique OCI label, the manifest digest
#   differs on every rebuild, so `upgrade` stages a fresh deployment each time.
#   (Without that label, a cache-rebuilt image has an identical digest and
#   `upgrade` would print "No update available.")
#
#   bootc upgrade
#
# Prereqs: (1) run ./build.sh first; (2) have adopted the image ONCE via
# ./switch.sh. bootc is shipped on Fedora Silverblue 44+. No --transport flag is
# needed — upgrade operates on the reference you're already booted on.
set -euo pipefail

FEDORA_MAJOR_VERSION="44"
IMAGE="localhost/host-image-thinkpad:${FEDORA_MAJOR_VERSION}"

# Sanity: the image must exist in root podman storage.
if ! sudo podman image exists "${IMAGE}"; then
  echo "Image ${IMAGE} not found in root podman storage." >&2
  echo "Run ./build.sh first." >&2
  exit 1
fi

echo "==> bootc upgrade  (re-resolves ${IMAGE} from local storage, compares digest)"
sudo bootc upgrade

cat <<EOF

New deployment staged. It is NOT active until you reboot:

  systemctl reboot

(Or re-run with --apply to reboot automatically:
  sudo bootc upgrade --apply)

After reboot, verify which build you're on:
  cat /usr/lib/host-image-thinkpad-version
  ./status.sh        # or: bootc status (Version + image digest)

If the new image is broken, the previous deployment is still there — roll back:
  ./rollback.sh      # then: systemctl reboot
EOF

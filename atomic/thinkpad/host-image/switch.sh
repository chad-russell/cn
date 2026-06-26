#!/usr/bin/env bash
# Adopt the custom image as the host's boot image — the ONE-TIME command to
# start booting from `containers-storage:localhost/host-image-thinkpad:44`
# (or to later re-point the host at a different image/tag). Uses the modern
# bootc front-end (not rpm-ostree).
#
#   bootc switch --transport containers-storage localhost/host-image-thinkpad:44
#
# Prereq: run ./build.sh first. bootc is shipped on Fedora Silverblue 44+.
#
# IMPORTANT — switch vs upgrade (don't get bitten by this):
#   `bootc switch` compares the image REFERENCE (transport + name + tag), NOT
#   the image content. Pointing it at the same `...:44` you're already booted
#   on is a no-op BY DESIGN ("Image specification is unchanged") — even if you
#   just rebuilt :44 with new content. So switch is for the FIRST adopt (or
#   changing to a different image/tag); it is NOT the routine rebuild command.
#   To apply a rebuilt image you're already booted on, use ./upgrade.sh, which
#   compares the image's manifest DIGEST and so detects content changes.
set -euo pipefail

FEDORA_MAJOR_VERSION="44"
IMAGE="localhost/host-image-thinkpad:${FEDORA_MAJOR_VERSION}"

# Sanity: the image must exist in root podman storage.
if ! sudo podman image exists "${IMAGE}"; then
  echo "Image ${IMAGE} not found in root podman storage." >&2
  echo "Run ./build.sh first." >&2
  exit 1
fi

echo "==> bootc switch --transport containers-storage ${IMAGE}"
echo "    (one-time adopt; for routine rebuilds use ./upgrade.sh)"
sudo bootc switch --transport containers-storage "${IMAGE}"

cat <<EOF

New deployment staged. It is NOT active until you reboot:

  systemctl reboot

(Or re-run with --apply to reboot automatically:
  sudo bootc switch --apply --transport containers-storage ${IMAGE})

After reboot, verify which build you're on:
  cat /usr/lib/host-image-thinkpad-version
  ./status.sh        # or: bootc status

Next time you rebuild the image, DON'T re-run switch.sh (it will say
"Image specification is unchanged" because the reference is the same) — run:
  ./build.sh && ./upgrade.sh     # then: systemctl reboot

If the new image is broken, the previous deployment is still there — roll back:
  ./rollback.sh      # then: systemctl reboot
EOF

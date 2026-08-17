#!/usr/bin/env bash
# Apply the latest bees-built image to the host — the ROUTINE command.
#
# Resolves the current bootc image reference (registry or containers-storage)
# and applies NEW CONTENT of that SAME reference:
#   - registry reference (the normal path since switch.sh adopted it):
#       bootc upgrade → pulls only the changed layers of
#       10.10.0.6:5000/cn/thinkpad-host:44 from bees's zot registry over
#       Nebula and stages the new deployment. Diff-only: a version-stamp-only
#       rebuild is a few MB; a Fedora-update rebuild is typically tens-hundreds.
#   - containers-storage reference (break-glass local flow, still works):
#       bootc upgrade → re-resolves localhost/host-image-thinkpad:44 from
#       root podman storage (no network) exactly like the old script.
#
# Prereqs: Nebula up (registry path). bootc ships on Silverblue 44+.
set -euo pipefail

REGISTRY="10.10.0.6:5000"

# If we're on the registry reference, pre-flight the registry so a Nebula
# outage produces a clear error instead of a deep containers-stack failure.
# (Grepping the address works for both bootc status output formats.)
if sudo bootc status 2>/dev/null | grep -q "${REGISTRY}"; then
  echo "==> on the registry reference — pre-flighting ${REGISTRY}"
  curl -fsSL --max-time 10 "http://${REGISTRY}/v2/" >/dev/null || {
    echo "ERROR: cannot reach ${REGISTRY} — is Nebula up on this host?" >&2
    echo "       (break-glass while offline: cjust image-build && cjust image-switch)" >&2
    exit 1
  }
else
  echo "==> not on the registry reference yet (local containers-storage flow)"
  echo "    one-time adopt of the registry flow:  cjust image-switch"
fi

echo "==> bootc upgrade"
sudo bootc upgrade

cat <<EOF

New deployment staged. It is NOT active until you reboot:

  systemctl reboot

(Or re-run with --apply to reboot automatically:
  sudo bootc upgrade --apply)

After reboot, verify which build you're on:
  cat /usr/lib/host-image-thinkpad-version
  bootc status       # Version + image digest

If the new image is broken, the previous deployment is still there — roll back:
  bootc rollback     # then: systemctl reboot
EOF

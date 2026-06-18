#!/usr/bin/env bash
#
# ARCHIVED container-based Vicinae helper.
# Current production path is host `vicinae` + `image/vicinae-bwrap`; see
# `vicinae/README.md`.
#
# Toggle (show/hide) the vicinae launcher running in the container.
# Extra args are forwarded, so you can also open deeplinks, e.g.:
#
#     ./toggle.sh vicinae://launch/clipboard/history
#
set -euo pipefail

CONTAINER="${VICINAE_CONTAINER:-vicinae}"
exec podman exec "${CONTAINER}" vicinae toggle "$@"

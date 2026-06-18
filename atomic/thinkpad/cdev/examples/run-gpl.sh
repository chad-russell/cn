#!/usr/bin/env bash
# Gross use-case script: edit the gpl repo while the quadlet stack serves :3006.
# Stack: systemctl --user start gpl-dev-app
set -euo pipefail
cd "$(dirname "$0")/.."
exec env \
  CDEV_HOME_VOLUME="${CDEV_HOME_VOLUME:-cdev-home-gpl}" \
  ./run.sh -w "${CDEV_WORKDIR:-$HOME/Gloo/360-gpl}" "$@"

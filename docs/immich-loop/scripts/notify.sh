#!/usr/bin/env bash
# notify.sh — post a message to Discord #infra via hermes send.
# Usage: bash docs/immich-loop/scripts/notify.sh "message"
set -euo pipefail
exec hermes send -t discord:#infra "$@"

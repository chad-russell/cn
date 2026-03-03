#!/usr/bin/env bash
# Privileged setup hook for Tailscale
# Automatically sets the first user as the operator

version-script tailscale privileged 1 || exit 0

set -xueo pipefail

tailscale set --operator="$(getent passwd "$PKEXEC_UID" | cut -d: -f1)"

#!/usr/bin/env bash
# Build the cdev sandbox image. Tags as localhost/cdev:latest (Podman's
# default registry prefix), which is what run.sh expects.
set -euo pipefail
podman build -t localhost/cdev:latest .

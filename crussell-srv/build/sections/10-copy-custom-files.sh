#!/usr/bin/env bash

set -eoux pipefail

echo "::group:: Copy Custom Files"

cp -a /ctx/oci/brew/. /

echo "::endgroup::"

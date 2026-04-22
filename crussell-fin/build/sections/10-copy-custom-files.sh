#!/usr/bin/env bash

set -eoux pipefail

echo "::group:: Copy Custom Files"

cp -a /ctx/oci/common/shared/. /
cp -a /ctx/oci/common/bluefin/. /
cp -a /ctx/oci/brew/. /

echo "::endgroup::"

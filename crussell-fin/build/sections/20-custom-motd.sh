#!/usr/bin/env bash

set -eoux pipefail

echo "::group:: Custom MOTD"

cp /ctx/build/motd.sh /usr/bin/ublue-motd
chmod +x /usr/bin/ublue-motd

echo "::endgroup::"

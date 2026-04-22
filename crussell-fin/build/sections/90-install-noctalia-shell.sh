#!/usr/bin/env bash

set -eoux pipefail

echo "::group:: Install Noctalia Shell"

FEDORA_VERSION=$(rpm -E %fedora)

cat > /etc/yum.repos.d/terra.repo <<EOF
[terra]
name=Terra ${FEDORA_VERSION}
baseurl=https://repos.fyralabs.com/terra${FEDORA_VERSION}/
enabled=0
gpgcheck=1
gpgkey=https://repos.fyralabs.com/terra${FEDORA_VERSION}/key.asc
EOF

dnf5 install -y --enablerepo=terra \
    noctalia-shell \
    cliphist \
    matugen

dnf5 config-manager setopt terra.enabled=0

echo "::endgroup::"

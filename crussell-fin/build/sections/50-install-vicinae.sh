#!/usr/bin/env bash

set -eoux pipefail

echo "::group:: Install Vicinae"

echo "Installing Vicinae and cmark-gfm dependency..."
dnf5 -y copr enable quadratech188/cmark-gfm
dnf5 -y copr enable quadratech188/vicinae
dnf5 -y install --enablerepo=copr:copr.fedorainfracloud.org:quadratech188:cmark-gfm --enablerepo=copr:copr.fedorainfracloud.org:quadratech188:vicinae vicinae
dnf5 -y copr disable quadratech188/vicinae
dnf5 -y copr disable quadratech188/cmark-gfm

echo "::endgroup::"

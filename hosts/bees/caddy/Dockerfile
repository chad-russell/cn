# caddy + the Route53 DNS-challenge plugin (github.com/caddy-dns/route53).
#
# Source of truth for the localhost/caddy-route53:latest image the caddy
# quadlet runs on bees. Until 2026-09-24 this image existed only as a
# hand-built artifact on bees — unrebuildable from the repo, while
# backup.nix excludes container image layers on the assumption that
# images are pullable. This one isn't: after a bees disk loss the TLS
# ingress for every *.internal.crussell.io service depended on
# re-deriving this build from memory.
#
# Built by caddy-image-build.service (hosts/bees/caddy.nix) at boot when
# the image is missing or this file's hash changed — podman's layer
# cache makes rebuilds incremental. The plugin is deliberately NOT
# version-pinned: xcaddy resolves a plugin release compatible with the
# builder's caddy; pin it if a build ever breaks upstream (the DR
# requirement is rebuildable, not bit-reproducible).
FROM docker.io/library/caddy:builder AS builder
RUN xcaddy build --with github.com/caddy-dns/route53

FROM docker.io/library/caddy:2
COPY --from=builder /usr/bin/caddy /usr/bin/caddy

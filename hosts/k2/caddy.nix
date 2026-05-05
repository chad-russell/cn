# ── Caddy Reverse Proxy (System Podman Quadlet) ──────────────────
#
# Migrated from hub's caddy.container. Uses the same caddy-route53
# image with Route53 DNS challenge for TLS certs.
#
# Prerequisites (run once before enabling):
#   1. Copy caddy-route53 image: podman load < caddy-route53.tar
#   2. Copy aws.env to /etc/caddy/aws.env with AWS credentials
#   3. Copy Caddyfile + routes to /etc/caddy/
#   4. Copy TLS data volumes from hub
#
# Deploy: systemctl daemon-reload && systemctl restart caddy

{ config, lib, pkgs, ... }:

{
  # ── Copy Caddy quadlet to systemd ───────────────────────────────
  environment.etc."containers/systemd/caddy.container" = {
    source = ./caddy/caddy.container;
    mode = "0644";
  };

  # ── Activation script to ensure caddy volumes exist ─────────────
  system.activationScripts.caddy-volumes = lib.stringAfter [ "users" ] ''
    ${pkgs.podman}/bin/podman volume create caddy_data 2>/dev/null || true
    ${pkgs.podman}/bin/podman volume create caddy_config 2>/dev/null || true
  '';
}

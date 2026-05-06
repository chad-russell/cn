# ── Caddy Reverse Proxy (System Podman Quadlet on k2) ───────────
#
# Uses a local caddy-route53 image with Route53 DNS challenge support.
#
# Prerequisites for a fresh k2 restore:
#   1. Copy/build caddy-route53 image: podman load < caddy-route53.tar
#   2. Copy aws.env to /etc/caddy/aws.env with AWS credentials.
#   3. Caddyfile + routes are installed declaratively into /etc/caddy/.
#   4. Restore caddy_data and caddy_config volumes if preserving ACME state.
#
# Deploy Nix changes: nix run .#deploy -- k2
# Restart service: systemctl restart caddy

{ config, lib, pkgs, ... }:

{
  # ── Install Caddy config and Quadlet ───────────────────────────
  environment.etc."containers/systemd/caddy.container" = {
    source = ./caddy/caddy.container;
    mode = "0644";
  };
  environment.etc."caddy/Caddyfile" = {
    source = ./caddy/Caddyfile;
    mode = "0644";
  };
  # Note: must NOT set mode on a directory source, otherwise Nix's
  # setup-etc.pl tries to copy() instead of symlink, which fails for dirs.
  environment.etc."caddy/routes".source = ./caddy/routes;

  # ── Activation script to ensure caddy volumes exist ─────────────
  system.activationScripts.caddy-volumes = lib.stringAfter [ "users" ] ''
    ${pkgs.podman}/bin/podman volume create caddy_data 2>/dev/null || true
    ${pkgs.podman}/bin/podman volume create caddy_config 2>/dev/null || true
  '';
}

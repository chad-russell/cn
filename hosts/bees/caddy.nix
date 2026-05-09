# ── Caddy Reverse Proxy (System Podman Quadlet on bees) ───────────
#
# Uses a local caddy-route53 image with Route53 DNS challenge.
#
# Caddy terminates TLS for both public (*.crussell.io) and internal
# (*.internal.crussell.io) domains. Routes point to localhost services
# or to other hosts on the LAN/Nebula.

{ config, lib, pkgs, ... }:

{
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

  system.activationScripts.caddy-volumes = lib.stringAfter [ "users" ] ''
    ${pkgs.podman}/bin/podman volume create caddy_data 2>/dev/null || true
    ${pkgs.podman}/bin/podman volume create caddy_config 2>/dev/null || true
  '';
}

# ── Caddy Reverse Proxy (System Podman Quadlet on bees) ───────────
#
# Uses a local caddy-route53 image with Route53 DNS challenge.
#
# Caddy terminates TLS for both public (*.crussell.io) and internal
# (*.internal.crussell.io) domains. Routes point to localhost services
# or to other hosts on the LAN/Nebula.

{ config, lib, pkgs, ... }:

{
  age.secrets.aws-env.file = ../../secrets/aws-env.age;

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

  # The caddy quadlet reads /etc/caddy only at container start. A NixOS
  # switch swaps the /etc content but nothing restarts the container,
  # so config/route changes silently don't apply — Caddy keeps serving
  # the old routes and new hostnames fall through to empty 200s (seen
  # with dsh.internal.crussell.io). Restart caddy only when the routes
  # store path or Caddyfile content actually changes. (The Caddyfile is
  # COPIED into /etc by setup-etc — mode is set — so its path never
  # changes; hash its content. The routes dir is a store symlink, so
  # its resolved path already covers all route files.)
  system.activationScripts.caddy-restart-on-config-change =
    lib.stringAfter [ "etc" ] ''
      MARKER=/var/lib/caddy-config-generation
      CURRENT="$(readlink -f /etc/caddy/routes) $(sha256sum /etc/caddy/Caddyfile | cut -d' ' -f1)"
      if [ -n "$CURRENT" ] && [ "$CURRENT" != "$(cat "$MARKER" 2>/dev/null)" ]; then
        ${pkgs.systemd}/bin/systemctl try-restart caddy.service || true
        printf '%s' "$CURRENT" > "$MARKER"
      fi
    '';
}

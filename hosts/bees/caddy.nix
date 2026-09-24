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
  environment.etc."caddy/Dockerfile" = {
    source = ./caddy/Dockerfile;
    mode = "0644";
  };

  # Build localhost/caddy-route53:latest from /etc/caddy/Dockerfile when
  # the image is missing or the Dockerfile's hash changed. Until
  # 2026-09-24 the image was a hand-built artifact with no source in
  # the repo — after a bees disk loss (restic excludes container image
  # layers, assuming images are pullable; this one isn't) the internal
  # TLS ingress was unrebuildable. Boot-ordered before caddy.service so
  # a reinstall's first boot builds the image before Caddy starts.
  systemd.services.caddy-image-build = {
    description = "Build localhost/caddy-route53 from the repo Dockerfile";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    before = [ "caddy.service" ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [ podman coreutils gnused ];
    onFailure = [ "ntfy-failure@caddy-image-build.service" ];
    serviceConfig = {
      Type = "oneshot";
      # A background rebuild must never compete with real load.
      Nice = 10;
      IOSchedulingClass = "idle";
    };
    script = ''
      set -euo pipefail
      MARKER=/var/lib/caddy-image-dockerfile-hash
      HASH="$(sha256sum /etc/caddy/Dockerfile | cut -d' ' -f1)"
      if [ "$(cat "$MARKER" 2>/dev/null)" = "$HASH" ] \
         && podman image inspect localhost/caddy-route53:latest >/dev/null 2>&1; then
        echo "caddy image up to date ($(podman image inspect --format '{{.Id}}' localhost/caddy-route53:latest | cut -c1-19))"
        exit 0
      fi
      echo "building localhost/caddy-route53:latest from /etc/caddy/Dockerfile"
      podman build -t localhost/caddy-route53:latest /etc/caddy/
      printf '%s' "$HASH" > "$MARKER"
      echo "build complete, marker updated"
    '';
  };

  system.activationScripts.caddy-volumes = lib.stringAfter [ "users" ] ''
    ${pkgs.podman}/bin/podman volume create caddy_data 2>/dev/null || true
    ${pkgs.podman}/bin/podman volume create caddy_config 2>/dev/null || true
  '';

  # bubblebox binary cache dir (served by the caddy route in
  # routes/internal/bubblebox.caddy; written by `cjust bubblebox-publish`
  # on the thinkpad over ssh/rsync as crussell).
  systemd.tmpfiles.settings."bubblebox-cache" = {
    "/var/lib/bubblebox-cache".d = {
      mode = "0755";
      user = "crussell";
      group = "users";
    };
  };

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
      CURRENT="$(readlink -f /etc/caddy/routes) $(sha256sum /etc/caddy/Caddyfile | cut -d' ' -f1) $(sha256sum /etc/caddy/Dockerfile | cut -d' ' -f1)"
      if [ -n "$CURRENT" ] && [ "$CURRENT" != "$(cat "$MARKER" 2>/dev/null)" ]; then
        # A changed Dockerfile means the image must be rebuilt BEFORE
        # caddy restarts onto it — systemctl start on the oneshot build
        # unit waits for completion.
        if [ "$(sha256sum /etc/caddy/Dockerfile | cut -d' ' -f1)" != "$(cat /var/lib/caddy-image-dockerfile-hash 2>/dev/null)" ]; then
          ${pkgs.systemd}/bin/systemctl start caddy-image-build.service
        fi
        # daemon-reload FIRST: route/Caddyfile edits only need a restart, but
        # QUADLET unit changes (e.g. a new Volume= in caddy.container) are
        # invisible to a restart until systemd re-reads the unit — without
        # this the container keeps its old mounts until a manual
        # daemon-reload + restart (seen when adding the bubblebox-cache
        # volume: the mount silently didn't land).
        ${pkgs.systemd}/bin/systemctl daemon-reload || true
        ${pkgs.systemd}/bin/systemctl try-restart caddy.service || true
        printf '%s' "$CURRENT" > "$MARKER"
      fi
    '';
}

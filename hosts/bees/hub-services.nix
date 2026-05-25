# ── Shared Web Services (Podman Quadlets on bees) ──────────────────
# Linkding, Papra, Open-WebUI.

{ config, lib, pkgs, ... }:

{
  environment.etc."containers/systemd/linkding.container" = {
    source = ./linkding.container;
    mode = "0644";
  };
  environment.etc."containers/systemd/papra.container" = {
    source = ./papra.container;
    mode = "0644";
  };
  environment.etc."containers/systemd/open-webui.container" = {
    source = ./open-webui.container;
    mode = "0644";
  };

  system.activationScripts.hub-services-dirs = lib.stringAfter [ "users" ] ''
    mkdir -p /srv/linkding/data
    mkdir -p /srv/papra/data
    mkdir -p /srv/open-webui/data

    if [ ! -f /var/lib/papra/auth.env ]; then
      mkdir -p /var/lib/papra
      TOKEN=$(head -c 32 /dev/urandom | base64 | tr -d '/+=\n' | head -c 32)
      printf 'AUTH_SECRET=%s\n' "$TOKEN" > /var/lib/papra/auth.env
      chmod 600 /var/lib/papra/auth.env
    fi
  '';
}

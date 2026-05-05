# ── Hub Services (Podman Quadlets) ───────────────────────────────
#
# Linkding, Papra, and Open-WebUI migrated from hub as Podman containers.
# Data lives in /srv/<service>/data/ on the host.
#
# Prerequisites (run once before enabling):
#   1. rsync data from hub: /srv/{linkding,papra,open-webui}/data -> /srv/ on k2
#   2. podman pull images (or they'll auto-pull on first start)
#
# Deploy: nix run .#deploy -- k2

{ config, lib, pkgs, ... }:

{
  # ── Install quadlets into systemd ───────────────────────────────
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

  # ── Ensure data directories exist ──────────────────────────────
  system.activationScripts.hub-services-dirs = lib.stringAfter [ "users" ] ''
    mkdir -p /srv/linkding/data
    mkdir -p /srv/papra/data
    mkdir -p /srv/open-webui/data
  '';
}

# ── Shared Web Services (Podman Quadlets on k2) ──────────────────
#
# Linkding, Papra, and Open-WebUI run as system Podman Quadlets.
# Data lives in /srv/<service>/data/ on k2.
#
# Prerequisites for a fresh k2 restore:
#   1. Restore /srv/{linkding,papra,open-webui}/data from backup/migration source.
#   2. podman pull images (or they'll auto-pull on first start).
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

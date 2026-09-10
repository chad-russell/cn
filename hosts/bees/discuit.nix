# ── Discuit (bees) ──────────────────────────────────────────────────
#
# Community discussion platform at discuit.internal.crussell.io —
# replaced Lemmy 2026-09-10 (deployed and removed the same day; the
# UI didn't land). Substrate for glen's transport #4 experiment (see
# glen: research/design/channel-3-4-candidates.md §5a).
#
# Shape: single upstream container (app + MariaDB + Redis inside,
# entrypoint starts both and runs migrations on every boot). Podman
# quadlet, the cn "system container" pattern. Port 8100 published on
# loopback only; the TLS-terminating Caddy fronts it via
# caddy/routes/internal/discuit.caddy.
#
# Image: no official registry image — built from source on bees at a
# pinned upstream rev, tagged localhost/discuit:<sha7>. Current pin:
#   7d8ca323fc3b0540ee19bd764c52805a05f82432 (discuitnet/discuit)
# Rebuild runbook (update the tag in discuit.container afterwards):
#   ssh bees
#   git clone https://github.com/discuitnet/discuit /tmp/discuit-build
#   cd /tmp/discuit-build && git checkout <rev>
#   sudo podman build -t localhost/discuit:<sha7> -f docker/Dockerfile.amd64 .
#
# Privacy posture (Chad 2026-09-10): signups closed, no public
# exposure. NOTE the difference from Lemmy: Discuit has no
# private-instance mode — anonymous users who can reach the site can
# READ it. The boundary is the network: *.internal.crussell.io
# resolves only to the Nebula overlay (10.10.0.6), and the port is
# loopback-published, so only overlay/LAN clients see it at all.
# Signups are disabled via the site-settings blob (application_data
# table, key "site_settings", JSON field "signupsDisabled") — set from
# the admin UI, or deterministically:
#   sudo podman exec discuit mysql discuit \
#     -e 'UPDATE application_data SET value = JSON_SET(value, "$.signupsDisabled", true) WHERE `key` = "site_settings";'
#   (restart discuit.service after a direct DB edit — settings are cached)
#
# First-boot runbook (verified 2026-09-10):
#   1. Visit https://discuit.internal.crussell.io, create the "chad"
#      account (signups are open until step 3).
#   2. sudo podman exec discuit /app/discuit admin make chad
#   3. Flip signupsDisabled (SQL above or admin UI), restart if SQL.
#   4. Verify: anonymous POST /api/_signup → 403 signups-disabled.
#
# Backup: the three named volumes live under
# /var/lib/containers/storage/volumes — already in backup.nix's paths.

{ config, lib, pkgs, ... }:

{
  age.secrets.discuit-env.file = ../../secrets/discuit-env.age;

  environment.etc."containers/systemd/discuit.container" = {
    source = ./discuit.container;
    mode = "0644";
  };

  environment.etc."discuit/config.yaml" = {
    source = ./discuit-config.yaml;
    mode = "0644";
  };

  system.activationScripts.discuit-volumes = lib.stringAfter [ "users" ] ''
    ${pkgs.podman}/bin/podman volume create discuit-db 2>/dev/null || true
    ${pkgs.podman}/bin/podman volume create discuit-redis 2>/dev/null || true
    ${pkgs.podman}/bin/podman volume create discuit-images 2>/dev/null || true
  '';
}

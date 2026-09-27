# ── bees: nightly podman auto-update for system quadlets ─────────────
#
# Opt-in per container via `AutoUpdate=registry` in the .container file
# (quadlet sets the io.containers.autoupdate=registry label). The nightly
# `podman auto-update` run compares the remote digest of each labeled
# tag against local storage; on drift it pulls and systemd restarts the
# unit onto the new image. Containers WITHOUT the label are never
# touched — caddy, immich (one-way DB migrations), jellyfin, openobserve
# (digest-pinned), zot (image-build infra) stay on the manual/PR path.
#
# Labeled today: linkding, papra, kan, sonarr, radarr, prowlarr,
# qbittorrent. kan-migrate is a oneshot unit (not a long-runner), so a
# label would do nothing there.
#
# Schedule: 04:30 + jitter, so image pulls and service restarts (brief
# API blips) land in the quiet hours. Persistent=true catches missed
# runs after downtime.
{ pkgs, ... }:

{
  systemd.services.podman-auto-update = {
    description =
      "podman auto-update (system quadlets with AutoUpdate=registry)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    # ntfy-failure@ template from modules/freshness-checks.nix
    onFailure = [ "ntfy-failure@podman-auto-update.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.podman}/bin/podman auto-update";
    };
  };

  systemd.timers.podman-auto-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:30";
      RandomizedDelaySec = "45min";
      Persistent = true;
    };
  };
}

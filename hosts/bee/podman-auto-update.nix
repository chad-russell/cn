# ── bee: nightly podman auto-update for rootless quadlets ────────────
#
# Opt-in per container via `AutoUpdate=registry` in the .container file
# (quadlet sets the io.containers.autoupdate=registry label). The nightly
# `podman auto-update` run compares the remote digest of each labeled
# tag against local storage; on drift it pulls and systemd restarts the
# unit onto the new image. Containers WITHOUT the label are never
# touched — pinned images (dev-quadlets) stay where they are.
#
# User-level (crussell's manager) because every long-running quadlet on
# bee is rootless; the system-level NixOS podman auto-update can't see
# rootless storage. Labeled today: ninerouter, hindsight, filebrowser.
#
# Schedule: 04:30 + jitter, so image pulls and service restarts (brief
# API blips) land in the quiet hours. Persistent=true catches missed
# runs after downtime.
{ pkgs, ... }:

{
  systemd.user.services.podman-auto-update = {
    description =
      "podman auto-update (rootless quadlets with AutoUpdate=registry)";
    unitConfig.ConditionUser = "crussell";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.podman}/bin/podman auto-update";
    };
  };

  systemd.user.timers.podman-auto-update = {
    wantedBy = [ "default.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:30";
      RandomizedDelaySec = "45min";
      Persistent = true;
    };
  };
}

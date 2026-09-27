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
{ config, pkgs, ... }:

{
  systemd.user.services.podman-auto-update = {
    description =
      "podman auto-update (rootless quadlets with AutoUpdate=registry)";
    onFailure = [ "ntfy-failure@podman-auto-update.service" ];
    unitConfig.ConditionUser = "crussell";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.podman}/bin/podman auto-update";
    };
  };

  # The freshness-checks ntfy-failure@ template lives in the SYSTEM
  # manager, but a user unit's OnFailure= resolves inside the USER
  # manager — so rootless units get their own mirror of the template
  # (same shape; ntfy URL from homelab.ntfyUrl).
  systemd.user.services."ntfy-failure@" = {
    description = "ntfy alert on user-service failure (%i)";
    serviceConfig.Type = "oneshot";
    scriptArgs = "%i";
    script = ''
      ${pkgs.curl}/bin/curl -fsS \
        -H "Title: FAILED — $1 on ${config.networking.hostName}" \
        -H "Tags: rotating_light" -H "Priority: high" \
        -d "User service '$1' failed on ${config.networking.hostName}. Inspect: journalctl --user -u $1" \
        "${config.homelab.ntfyUrl}" >/dev/null 2>&1 || true
    '';
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

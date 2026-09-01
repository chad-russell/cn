# ── bees: zot registry + thinkpad host-image build service ─────────
#
# Serves the thinkpad's bootc host image over Nebula (10.10.0.6:5000, plain
# HTTP inside the WireGuard tunnel) and builds/publishes it daily.
#
# Flow: thinkpad-image-build.timer (daily ~05:10) → thinkpad-image-build.service
#   → git pull ~/Code/cn → podman build hosts/thinkpad/host-image/Containerfile
#   → push to 10.10.0.6:5000/cn/thinkpad-host:{44, 44-<sha>-<ts>}
# On the thinkpad: `cjust image-upgrade` → `bootc upgrade` pulls only the
# changed layers and stages the deployment; it goes live on next reboot.
#
# zot retention (zot-config.json): keeps the rolling :44 forever and the last
# 3 immutable 44-* tags; everything else is GC'd (blobs reclaimed hourly-ish).

{ config, lib, pkgs, ... }:

{
  # ---- zot registry (Podman quadlet, Nebula-bound) ------------------
  environment.etc."containers/systemd/zot.container" = {
    source = ./zot.container;
    mode = "0644";
  };
  environment.etc."zot/config.json" = {
    source = ./zot-config.json;
    mode = "0644";
  };
  system.activationScripts.zot-dirs = lib.stringAfter [ "users" ] ''
    mkdir -p /var/lib/zot
  '';

  # ---- thinkpad host-image build + publish --------------------------
  environment.etc."thinkpad-image-build.sh" = {
    source = ./thinkpad-image-build.sh;
    mode = "0755";
  };
  environment.etc."thinkpad-build-storage.conf" = {
    source = ./thinkpad-build-storage.conf;
    mode = "0644";
  };

  systemd.services.thinkpad-image-build = {
    description = "Build + publish thinkpad host image to zot registry";
    after = [ "network-online.target" "zot.service" ];
    wants = [ "network-online.target" ];
    # oneshot: a build already in flight must not be raced by a second one
    #
    # path is REQUIRED: systemd units don't inherit the login PATH, so the
    # script's `#!/usr/bin/env bash` can't resolve bash without it (NixOS has
    # no /bin/bash). This also provides git/podman/coreutils for the script.
    # util-linux: runuser (git runs as crussell, the repo owner)
    # openssh: git fetch/push over SSH (origin is git@github.com), exec'd by
    # git from PATH as crussell (uses their ~/.ssh key)
    path = [
      pkgs.bash
      pkgs.coreutils
      pkgs.git
      pkgs.openssh
      pkgs.podman
      pkgs.util-linux
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${config.environment.etc."thinkpad-image-build.sh".source}";
      # Root: podman build must write root's containers-storage. git runs as
      # crussell via runuser inside the script (avoids dubious-ownership
      # errors and root-owned files landing in the crussell-owned tree).
      User = "root";
      Nice = 10;
      # Dedicated btrfs-driver build store (see thinkpad-build-storage.conf):
      # native subvolume snapshot layer commits instead of the FUSE fallback
      # the shared overlay-on-btrfs store suffers from. The push to zot goes
      # over HTTP to 10.10.0.6:5000 and doesn't read this store at all.
      Environment = [ "CONTAINERS_STORAGE_CONF=/etc/thinkpad-build-storage.conf" ];
    };
    onFailure = [ "ntfy-failure@thinkpad-image-build.service" ];
  };

  systemd.timers.thinkpad-image-build = {
    description = "Daily thinkpad host-image build";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # 05:10 local (America/New_York) — after the 05:00 restic backup window
      OnCalendar = "05:10";
      Persistent = true;
    };
  };
}

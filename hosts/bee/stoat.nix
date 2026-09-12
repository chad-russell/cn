# Stoat (ex-Revolt) instance — production hosting on bee.
#
# The live glen chat surface. 16-container compose mesh
# (mongo/valkey/rabbit/minio/livekit/caddy/…) — no nixpkgs module exists,
# so fleet-idiomatic: compose project at ~/stoat/upstream (user-owned),
# lifecycle managed by this unit as a rootless user service over the
# podman socket. Images/volumes in user podman storage (backed up via
# hosts/bee/backup.nix allowlist).
#
# Network: stack caddy publishes 0.0.0.0:8880; bees fronts it at
# https://stoat.internal.crussell.io (routes/internal/stoat.caddy).
# livekit UDP 7881 + 50000-50100 published (video off in config, kept
# for future use). The glen channel-stoat plugin talks REST loopback
# (127.0.0.1:8880/api) and discovers WS via the server config endpoint
# (domain URLs since the 2026-09-12 promotion).
#
# `systemctl start/stop stoat` = compose up/down (stop PRESERVES volumes —
# never `down -v` unless wiping the instance).
{ config, pkgs, ... }:

{
  systemd.services.stoat = {
    description = "Stoat (ex-Revolt) chat — rootless compose stack for glen";
    wants = [ "network-online.target" "podman-user.socket" ];
    after = [ "network-online.target" "podman-user.socket" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "crussell";
      WorkingDirectory = "/home/crussell/stoat/upstream";
      Environment = [
        "XDG_RUNTIME_DIR=/run/user/1000"
        "DOCKER_HOST=unix:///run/user/1000/podman/podman.sock"
      ];
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
      TimeoutStartSec = 300;
      TimeoutStopSec = 120;
    };

    wantedBy = [ "multi-user.target" ];
  };
}

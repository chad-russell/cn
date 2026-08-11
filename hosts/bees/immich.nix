# ── Immich Photo Server ───────────────────────────────────────────
# Photos are on NFS at /mnt/photos (already mounted in configuration.nix).

{ config, lib, pkgs, ... }:

{
  services.immich = {
    enable = true;
    host = "0.0.0.0";
    port = 2283;
    openFirewall = true;
    mediaLocation = "/mnt/photos";
    machine-learning.enable = true;
  };

  # Immich needs read access to the NFS photos mount.
  # NAS files are owned by crussell:users (gid 100); add immich to that
  # group so it can traverse directories with "other" permissions denied.
  users.groups.nas-photos = { gid = 1000; };
  users.users.immich.extraGroups = [ "nas-photos" "users" ];
  systemd.services.immich-server.serviceConfig.SupplementaryGroups =
    [ "redis-immich" "nas-photos" "users" ];

  # Reduce Redis log verbosity
  services.redis.servers.immich.logLevel = "warning";
}

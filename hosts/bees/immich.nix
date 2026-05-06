# ── Immich Photo Server ───────────────────────────────────────────
# Migrated from k4 (192.168.20.64).
# Photos are on NFS at /mnt/photos (already mounted in configuration.nix).
# PostgreSQL data must be transferred from k4 before starting.

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

  # Immich needs read access to the NFS photos mount for external library.
  # NAS files are owned by gid 1000; add immich to that group so it can
  # traverse directories with "other" permissions denied.
  users.groups.nas-photos = { gid = 1000; };
  users.users.immich.extraGroups = [ "nas-photos" ];
  systemd.services.immich-server.serviceConfig.SupplementaryGroups = [
    "redis-immich"
    "nas-photos"
  ];

  # Reduce Redis log verbosity
  services.redis.servers.immich.logLevel = "warning";
}

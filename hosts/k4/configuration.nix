{ config, lib, pkgs, ... }:

{
  imports = [
    ../../modules/elitedesk-hardware.nix
    ../../modules/base-server.nix
    ../../modules/elitedesk-disk-config.nix
    ../../modules/nebula-client.nix
  ];

  networking.hostName = "k4";

  # ── Networking ───────────────────────────────────────────────────
  systemd.network.networks."40-eno1" = {
    matchConfig.Name = "eno1";
    networkConfig.DHCP = "no";
    address = [ "192.168.20.64/24" ];
    routes = [{ Gateway = "192.168.20.1"; }];
    dns = [ "8.8.8.8" "1.1.1.1" ];
  };

  # ── NFS: Photos from NAS (Immich media location, read-write) ──
  fileSystems."/mnt/photos" = {
    device = "192.168.20.31:/mnt/tank/photos";
    fsType = "nfs";
    options = [ "defaults" "_netdev" "rw" "hard" "intr" ];
  };

  # ── NFS: Backups from NAS ───────────────────────────────────────
  fileSystems."/mnt/backups" = {
    device = "192.168.20.31:/mnt/tank/backups";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "timeo=14" "nfsvers=4" "rw" "soft" "intr" ];
  };

  # ── Immich ──────────────────────────────────────────────────────
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
  #
  # The NixOS immich module sets SupplementaryGroups=redis-immich on the
  # systemd service, which overrides the user's natural group membership.
  # We must explicitly add nas-photos to the service's SupplementaryGroups
  # for the external library scan to read the NFS-mounted photos.
  users.groups.nas-photos = { gid = 1000; };
  users.users.immich.extraGroups = [ "nas-photos" ];
  systemd.services.immich-server.serviceConfig.SupplementaryGroups = [
    "redis-immich"
    "nas-photos"
  ];

  # Reduce Redis log verbosity
  services.redis.servers.immich.logLevel = "warning";

  # ── Nebula ──────────────────────────────────────────────────────
  services.nebula.networks.homelab.enable = true;

  # ── State version ───────────────────────────────────────────────
  system.stateVersion = "25.05";
}

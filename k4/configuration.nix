{ config, pkgs, ... }:

{
  imports = [
    # Shared common configuration
    ../common/base-configuration.nix
    ../common/hardware-watchdog.nix
    ../common/network-optimizations.nix
    # Service modules (shared)
    ../services/beszel.nix
    ../services/beszel-agent.nix
    ../services/immich.nix
    ../modules/container-backup.nix
  ];

  # Set your hostname.
  networking.hostName = "k4";

  # Beszel agent authentication key (get from beszel hub when adding system)
  virtualisation.oci-containers.containers.beszel-agent.environment.KEY = 
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBZIx3DijQERcOTAbdQJmDSaTlI+20O8kE19iWyh8Fn5";

  # Mount NFS share from TrueNAS for Immich photos
  fileSystems."/mnt/immich" = {
    device = "192.168.20.31:/mnt/tank/photos";
    fsType = "nfs";
    options = [ 
      "nfsvers=4"
      "rw"
      "soft"
      "intr"
      "timeo=30"
      "retrans=3"
    ];
  };

  # Enable NFS client support
  services.rpcbind.enable = true;

  # Configure network interface
  systemd.network.networks."40-eth0" = {
    matchConfig.Name = "eno1";
    networkConfig.DHCP = "no";
    address = [ "192.168.20.64/24" ];
    routes = [
      { routeConfig.Gateway = "192.168.20.1"; }
    ];
    dns = [ "192.168.10.1" "8.8.8.8" ];
  };

  # Configure container backups
  services.containerBackup = {
    enable = true;
    jobs = {
      beszel = {
        containerName = "beszel";
        volumes = [ "beszel-data" ];
      };
      immich-postgres = {
        containerName = "immich-postgres";
        volumes = [ "immich-pgdata" ];
      };
    };
  };
}

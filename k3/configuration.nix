{ config, pkgs, ... }:

{
  imports = [
    # Shared common configuration
    ../common/base-configuration.nix
    ../common/hardware-watchdog.nix
    ../common/network-optimizations.nix
    # Service modules (shared)
    ../services/beszel-agent.nix
    ../modules/container-backup.nix
  ];

  # Set your hostname.
  networking.hostName = "k3";

  # Beszel agent authentication key (get from beszel hub when adding system)
  virtualisation.oci-containers.containers.beszel-agent.environment.KEY = 
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBZIx3DijQERcOTAbdQJmDSaTlI+20O8kE19iWyh8Fn5";

  # Configure network interface
  systemd.network.networks."40-eth0" = {
    matchConfig.Name = "eno1";
    networkConfig.DHCP = "no";
    address = [ "192.168.20.63/24" ];
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
      n8n = {
        containerName = "n8n";
        volumes = [ "n8n-data" "n8n-files" ];
      };
      onyx-db = {
        containerName = "onyx-relational-db";
        volumes = [ "onyx-db-volume" ];
      };
      onyx-vespa = {
        containerName = "onyx-index";
        volumes = [ "onyx-vespa-volume" ];
      };
      onyx-minio = {
        containerName = "onyx-minio";
        volumes = [ "onyx-minio-data" ];
      };
      pinepods-db = {
        containerName = "pinepods-db";
        volumes = [ "pinepods-pgdata" ];
      };
      searxng-valkey = {
        containerName = "searxng-valkey";
        volumes = [ "searxng-valkey-data" ];
      };
      searxng = {
        containerName = "searxng";
        volumes = [ "searxng-config" ];
      };
    };
  };
}

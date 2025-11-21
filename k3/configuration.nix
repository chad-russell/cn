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
    ../services/n8n.nix
    ../services/pinepods.nix
    ../services/searxng.nix
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
        serviceName = "docker-beszel.service";
        volumes = [ "beszel-data" ];
      };
      n8n = {
        containerName = "n8n";
        serviceName = "docker-n8n.service";
        volumes = [ "n8n-data" "n8n-files" ];
      };
      pinepods-db = {
        containerName = "pinepods-db";
        serviceName = "docker-pinepods-db.service";
        volumes = [ "pinepods-pgdata" ];
      };
      searxng-valkey = {
        containerName = "searxng-valkey";
        serviceName = "docker-searxng-valkey.service";
        volumes = [ "searxng-valkey-data" ];
      };
      searxng = {
        containerName = "searxng";
        serviceName = "docker-searxng.service";
        volumes = [ "searxng-config" ];
      };
    };
  };
}

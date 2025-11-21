{ config, pkgs, ... }:

{
  imports = [
    # Shared common configuration
    ../common/base-configuration.nix
    ../common/hardware-watchdog.nix
    ../common/network-optimizations.nix
    # Service modules (shared)
    ../services/beszel-agent.nix
    ../services/karakeep.nix
    ../services/memos.nix
    ../services/ntfy.nix
    ../services/papra.nix
    ../modules/container-backup.nix
  ];

  # Set your hostname.
  networking.hostName = "k2";

  # Beszel agent authentication key (get from beszel hub when adding system)
  virtualisation.oci-containers.containers.beszel-agent.environment.KEY = 
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBZIx3DijQERcOTAbdQJmDSaTlI+20O8kE19iWyh8Fn5";

  # Configure network interface
  systemd.network.networks."40-eth0" = {
    matchConfig.Name = "eno1";
    networkConfig.DHCP = "no";
    address = [ "192.168.20.62/24" ];
    routes = [
      { routeConfig.Gateway = "192.168.20.1"; }
    ];
    dns = [ "192.168.10.1" "8.8.8.8" ];
  };

  # Open firewall for Caddy reverse proxy
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # Configure container backups
  services.containerBackup = {
    enable = true;
    backend = "docker";
    jobs = {
      karakeep-app = {
        containerName = "karakeep";
        serviceName = "docker-karakeep.service";
        volumes = [ "karakeep-app-data" ];
      };
      karakeep-meili = {
        containerName = "karakeep-meilisearch";
        serviceName = "docker-karakeep-meilisearch.service";
        volumes = [ "karakeep-data" ];
      };
      karakeep-homedash = {
        containerName = "karakeep-homedash";
        serviceName = "docker-karakeep-homedash.service";
        volumes = [ "karakeep-homedash-config" ];
      };
      memos = {
        containerName = "memos";
        serviceName = "docker-memos.service";
        volumes = [ "memos-data" ];
      };
      ntfy = {
        containerName = "ntfy";
        serviceName = "docker-ntfy.service";
        volumes = [ "ntfy-config" "ntfy-cache" ];
      };
      papra = {
        containerName = "papra";
        serviceName = "docker-papra.service";
        volumes = [ "papra-data" ];
      };
    };
  };
}

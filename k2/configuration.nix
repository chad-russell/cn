{ config, pkgs, ... }:

{
  imports = [
    # Shared common configuration
    ../common/base-configuration.nix
    ../common/hardware-watchdog.nix
    ../common/network-optimizations.nix
    # Service modules (shared)
    # Backup module
    ../modules/python-backup.nix
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

  # Enable the Python backup script timer
  services.pythonContainerBackup = {
    enable = true;
    scriptPath = "/home/crussell/docker/backup.py";
  };
}

{ config, pkgs, ... }:

{
  imports = [
    # Shared common configuration
    ../common/base-configuration.nix
    ../common/hardware-watchdog.nix
    ../common/network-optimizations.nix
    ../common/nfs-backup-mount.nix
    # Backup module
    ../modules/python-backup.nix
  ];

  # Set your hostname.
  networking.hostName = "k3";

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
  
  # Enable the Python backup script timer
  services.pythonContainerBackup = {
    enable = true;
    scriptPath = "/home/crussell/docker/backup.py";
  };
}

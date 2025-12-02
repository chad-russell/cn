{ config, pkgs, ... }:

{
  imports = [
    # Shared common configuration
    ../common/base-configuration.nix
    ../common/hardware-watchdog.nix
    ../common/network-optimizations.nix
    # Backup module
    ../modules/python-backup.nix
  ];

  # Set your hostname.
  networking.hostName = "k4";

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

  # Enable the Python backup script timer
  services.pythonContainerBackup = {
    enable = true;
    scriptPath = "/home/crussell/docker/backup.py";
  };
}

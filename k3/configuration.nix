{ config, pkgs, ... }:

{
  imports = [
    # Shared common configuration
    ../common/base-configuration.nix
    ../common/hardware-watchdog.nix
    ../common/network-optimizations.nix
    ../common/nfs-backup-mount.nix
    ../common/elitedesk-fixes.nix
    ../common/k3s-ha.nix
    # Backup module
    ../modules/container-backup.nix
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
    dns = [ "8.8.8.8" ];
  };

  networking.firewall.allowedTCPPorts = [ 80 443 6443 2379 2380 10250 10251 10252 10257 10259 ];
  networking.firewall.allowedUDPPorts = [ 8472 ];

  services.k3s = {
    enable = true;
    role = "server";
    serverAddr = "https://192.168.20.32:6443";
    tokenFile = "/var/lib/rancher/k3s/server/node-token";
    extraFlags = [
      "--tls-san=192.168.20.32"
      "--node-ip=192.168.20.63"
      "--advertise-address=192.168.20.63"
    ];
  };

  # Enable the Python backup script timer
  services.containerBackup = {
    enable = true;
    scriptPath = "/home/crussell/cn/docker/backup.py";
    configPath = "/home/crussell/cn/k3/docker/backup-config.json";
  };
}

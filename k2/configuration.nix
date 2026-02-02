{ config, pkgs, ... }:

{
  imports = [
    # Shared common configuration
    ../common/base-configuration.nix
    ../common/hardware-watchdog.nix
    ../common/network-optimizations.nix
    ../common/nfs-backup-mount.nix
    ../common/elitedesk-fixes.nix
    # Backup system (restic-based)
    ../modules/restic-backup.nix
  ];

  # Set your hostname.
  networking.hostName = "k2";

  # Configure network interface
  systemd.network.networks."40-eth0" = {
    matchConfig.Name = "eno1";
    networkConfig.DHCP = "no";
    address = [ "192.168.20.62/24" ];
    routes = [
      { routeConfig.Gateway = "192.168.20.1"; }
    ];
    dns = [ "8.8.8.8" "1.1.1.1" ];
  };

  # Open firewall for Caddy reverse proxy
  # networking.firewall.allowedTCPPorts = [ 80 443 ];
  
  # Enable restic backups
  services.resticBackup = {
    enable = true;
    configPath = "/etc/restic-backup.json";
    passwordFile = "/etc/restic-password";
    repository = "/mnt/backups/restic";
    schedule = "03:00:00";
    ntfyUrl = "http://192.168.20.62:30085/restic-backup-failures";
  };
}

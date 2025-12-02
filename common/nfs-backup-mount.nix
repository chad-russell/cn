{ config, lib, pkgs, ... }:

{
  # Enable NFS client support
  services.rpcbind.enable = true;

  # Mount the NFS backup share
  fileSystems."/mnt/backups" = {
    device = "192.168.20.31:/mnt/tank/backups";
    fsType = "nfs";
    options = [ 
      "x-systemd.automount" 
      "noauto" 
      "timeo=14" 
      "nfsvers=4"
      "rw"
      "soft"
      "intr"
    ];
  };
}


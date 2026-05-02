{ config, lib, pkgs, ... }:

{
  imports = [
    ../../modules/elitedesk-hardware.nix
    ../../modules/base-server.nix
    # k3 was installed with its own disk layout (512M EFI, 8G swap, ext4 root)
    # NOT the standard elitedesk layout. Use the original disk-config.
    ../../servers/k3/disk-config.nix
    # ../../modules/nebula-client.nix  # Enable once certs are deployed
    ./media-services.nix
    ./gloo.nix
  ];

  networking.hostName = "k3";

  # ── Networking ───────────────────────────────────────────────────
  systemd.network.networks."40-eno1" = {
    matchConfig.Name = "eno1";
    networkConfig.DHCP = "no";
    address = [ "192.168.20.63/24" ];
    routes = [{ Gateway = "192.168.20.1"; }];
    dns = [ "8.8.8.8" "1.1.1.1" ];
  };

  # ── Local HDD mount ─────────────────────────────────────────────
  fileSystems."/mnt/data" = {
    device = "/dev/disk/by-uuid/e9c12a3f-6a65-458f-bd9b-ac46537e8839";
    fsType = "ext4";
    options = [ "defaults" "nofail" ];
  };

  # ── NFS: Media from NAS ─────────────────────────────────────────
  fileSystems."/mnt/media" = {
    device = "192.168.20.31:/mnt/tank/media";
    fsType = "nfs";
    options = [ "defaults" "_netdev" "rw" "hard" "intr" ];
  };

  # ── NFS: Backups from NAS ───────────────────────────────────────
  fileSystems."/mnt/backups" = {
    device = "192.168.20.31:/mnt/tank/backups";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "timeo=14" "nfsvers=4" "rw" "soft" "intr" ];
  };

  # ── Nebula ──────────────────────────────────────────────────────
  services.nebula.networks.homelab.enable = false;  # Enable after certs deployed

  # ── State version ───────────────────────────────────────────────
  system.stateVersion = "25.11";
}

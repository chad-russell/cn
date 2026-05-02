{ config, lib, pkgs, ... }:

{
  imports = [
    ../../modules/elitedesk-hardware.nix
    ../../modules/base-server.nix
    ../../modules/elitedesk-disk-config.nix
    # ../../modules/nebula-client.nix  # Enable once certs are deployed
  ];

  networking.hostName = "k2";

  # ── Networking ───────────────────────────────────────────────────
  systemd.network.networks."40-eno1" = {
    matchConfig.Name = "eno1";
    networkConfig.DHCP = "no";
    address = [ "192.168.20.62/24" ];
    routes = [{ Gateway = "192.168.20.1"; }];
    dns = [ "8.8.8.8" "1.1.1.1" ];
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

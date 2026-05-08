{ config, lib, pkgs, ... }:

{
  imports = [
    ../../modules/elitedesk-hardware.nix
    ../../modules/elitedesk-disk-config.nix
    ../../modules/base-server.nix
  ];

  networking.hostName = "k3";

  # ── Networking ───────────────────────────────────────────────────
  systemd.network.enable = true;
  networking.useDHCP = false;
    
  systemd.network.networks."40-eno1" = {
    matchConfig.Name = "eno1";
    networkConfig.DHCP = "no";
    address = [ "192.168.20.63/24" ];
    routes = [{ Gateway = "192.168.20.1"; }];
    dns = [ "8.8.8.8" "1.1.1.1" ];
  };

  # ── State version ───────────────────────────────────────────────
  system.stateVersion = "25.11";
}

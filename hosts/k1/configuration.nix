{ config, lib, pkgs, unstable, ... }:

{
  imports = [
    ../../modules/elitedesk-hardware.nix
    ../../modules/base-server.nix
    ../../modules/elitedesk-disk-config.nix
    ../../modules/nebula-client.nix
    ./gloo.nix
    ./buildspace.nix
  ];

  networking.hostName = "k1";

  # ── Networking ───────────────────────────────────────────────────
  systemd.network.networks."40-eno1" = {
    matchConfig.Name = "eno1";
    networkConfig.DHCP = "no";
    address = [ "192.168.20.61/24" ];
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
  services.nebula.networks.homelab.enable = true;

  # ── Gloo / Buildspace dev stacks ────────────────────────────────
  # These are mutually exclusive — enable only the one you're working on.
  services.gloo.enable = true;
  # services.buildspace.enable = true;

  # ── Dev tools ────────────────────────────────────────────────────
  environment.systemPackages = [
    pkgs.bun
    pkgs.nodejs
    unstable."pi-coding-agent"
  ];

  # ── State version ───────────────────────────────────────────────
  system.stateVersion = "25.11";
}

{ config, lib, pkgs, ... }:

{
  imports = [
    ../../modules/elitedesk-hardware.nix
    ../../modules/elitedesk-disk-config.nix
  ];

  networking.hostName = "k4";

  # ── Networking ───────────────────────────────────────────────────
  systemd.network.enable = true;
  networking.useDHCP = false;
  networking.nameservers = [ "8.8.8.8" "1.1.1.1" ];

  systemd.network.networks."40-eno1" = {
    matchConfig.Name = "eno1";
    networkConfig.DHCP = "no";
    address = [ "192.168.20.64/24" ];
    routes = [{ Gateway = "192.168.20.1"; }];
    dns = [ "8.8.8.8" "1.1.1.1" ];
  };

  # ── SSH (for deployment access) ─────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = true;
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOpNEpdHo8X0L9rgsJ+8fuXA4DodZftJaCd3Q6eCrVsw crussell@fedora"
  ];

  # ── Minimal packages ─────────────────────────────────────────────
  environment.systemPackages = with pkgs; [ vim curl ];

  # ── State version ───────────────────────────────────────────────
  system.stateVersion = "25.05";
}

# Decommissioned: all services migrated to bees (192.168.20.41).
# This host is retained only for hardware salvage or future repurposing.

{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # ── Boot ──────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ── Networking ───────────────────────────────────────
  networking.hostName = "k3";
  networking.networkmanager.enable = false;
  networking.useDHCP = false;

  networking.interfaces.eno1.ipv4.addresses = [{
    address = "192.168.20.26";
    prefixLength = 24;
  }];
  networking.defaultGateway = "192.168.20.1";
  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];

  # ── Time / Locale ───────────────────────────────────
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # ── Users ───────────────────────────────────────────
  users.users.crussell = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "changeme";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILQwJo2dYiyN5uaU56GoIclYuJS/Gi7T5kSV3C2Cd5YK chaddouglasrussell@gmail.com"
    ];
  };

  # Passwordless sudo for initial setup (tighten later)
  security.sudo.wheelNeedsPassword = false;

  # ── SSH ─────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true; # keep on until key-only is verified
    };
  };

  # ── Packages ────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    htop
  ];

  # ── Nix ─────────────────────────────────────────────
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # ── Firewall ────────────────────────────────────────
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  # ── State version ───────────────────────────────────
  system.stateVersion = "25.11";
}

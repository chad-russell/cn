# ── Base Server Configuration ──────────────────────────────────────
#
# Shared config for all server hosts (k1-k4, hub).
# Thinkpad is NOT a server and has its own config.

{ config, lib, pkgs, ... }:

{
  imports = [
    ./server-shell.nix
    ./nebula-hosts.nix
  ];

  # ── Time / Locale ────────────────────────────────────────────────
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # ── Users ────────────────────────────────────────────────────────
  users.users.crussell = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOpNEpdHo8X0L9rgsJ+8fuXA4DodZftJaCd3Q6eCrVsw crussell@fedora"
    ];
    initialPassword = "changeme";
  };
  security.sudo.wheelNeedsPassword = false;

  # Root SSH keys (for nixos-anywhere and emergency access)
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOpNEpdHo8X0L9rgsJ+8fuXA4DodZftJaCd3Q6eCrVsw crussell@fedora"
  ];

  # ── SSH ──────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = true;
    };
  };

  # ── Networking (systemd-networkd) ────────────────────────────────
  systemd.network.enable = true;
  networking.useDHCP = false;
  networking.nameservers = [ "8.8.8.8" "1.1.1.1" ];

  # ── Base packages ────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    htop
    jq
    ethtool
    nfs-utils
    ripgrep
    fd
  ];

  # ── Nix settings ─────────────────────────────────────────────────
  nix.settings.trusted-users = [ "root" "crussell" ];
  nix.settings.auto-optimise-store = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
    persistent = true;
    randomizedDelaySec = "10m";
  };

  # ── NFS client support ───────────────────────────────────────────
  services.rpcbind.enable = true;
}

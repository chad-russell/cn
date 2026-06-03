# ── Base Server Configuration ──────────────────────────────────────
#
# Shared config for all server hosts (bee, bees, misc).
# Thinkpad is NOT a server and has its own config.

{ config, lib, pkgs, unstable, ... }:

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
  networking.enableIPv6 = false;

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
    antigravity-cli
    unstable.cursor-cli
  ];

  # ── Allow unfree packages ────────────────────────────────────────
  nixpkgs.config.allowUnfree = true;

  # ── Nix settings ─────────────────────────────────────────────────
  nix.settings.trusted-users = [ "root" "crussell" ];
  nix.settings.auto-optimise-store = true;

  boot.loader.systemd-boot.configurationLimit = 15;
  boot.loader.grub.configurationLimit = 15;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    persistent = true;
    randomizedDelaySec = "10m";
  };

  systemd.services.nix-gc.preStart = ''
    ${config.nix.package.out}/bin/nix-env --delete-generations +15 -p /nix/var/nix/profiles/system
  '';

  # ── NFS client support ───────────────────────────────────────────
  services.rpcbind.enable = true;

  # ── Prometheus node exporter (for homelab monitoring) ────────────
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    openFirewall = true;
  };
}

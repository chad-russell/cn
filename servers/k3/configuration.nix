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

  # ── NFS: Media from NAS ─────────────────────────────
  fileSystems."/mnt/media" = {
    device = "192.168.20.31:/mnt/tank/media";
    fsType = "nfs";
    options = [ "defaults" "_netdev" "rw" "hard" "intr" ];
  };

  # ── Local HDD ───────────────────────────────────────
  # /dev/sda1 — 1.8T, mounted for torrent downloads
  # (avoids active torrent I/O going over NFS)
  fileSystems."/mnt/data" = {
    device = "/dev/disk/by-uuid/e9c12a3f-6a65-458f-bd9b-ac46537e8839";
    fsType = "ext4";
    options = [ "defaults" "nofail" ];
  };

  # ── Time / Locale ───────────────────────────────────
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # ── Shared media group ──────────────────────────────
  # All media services are added to this group so they can
  # read/write the NFS media mount and local data disk.
  users.groups.media = { gid = 2000; };

  # ── Users ───────────────────────────────────────────
  users.users.crussell = {
    isNormalUser = true;
    extraGroups = [ "wheel" "media" ];
    initialPassword = "changeme";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILQwJo2dYiyN5uaU56GoIclYuJS/Gi7T5kSV3C2Cd5YK chaddouglasrussell@gmail.com"
    ];
  };
  security.sudo.wheelNeedsPassword = false;

  # ── Jellyfin ────────────────────────────────────────
  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };
  users.users.jellyfin.extraGroups = [ "media" ];

  # ── Sonarr ──────────────────────────────────────────
  services.sonarr = {
    enable = true;
    openFirewall = true;
    group = "media";
  };

  # ── Radarr ──────────────────────────────────────────
  services.radarr = {
    enable = true;
    openFirewall = true;
    group = "media";
  };

  # ── Prowlarr ────────────────────────────────────────
  services.prowlarr = {
    enable = true;
    openFirewall = true;
    group = "media";
  };

  # ── Jellyseerr ──────────────────────────────────────
  services.jellyseerr = {
    enable = true;
    openFirewall = true;
    port = 5055;
  };
  # Jellyseerr uses DynamicUser — give it access to media via ACL
  # since we can't assign a static group.
  # Alternatively, override to use the media group:
  systemd.services.jellyseerr.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "jellyseerr";
    Group = "media";
    StateDirectory = "jellyseerr";
  };
  users.users.jellyseerr = {
    isSystemUser = true;
    group = "media";
    home = "/var/lib/jellyseerr";
  };

  # ── qBittorrent ─────────────────────────────────────
  services.qbittorrent = {
    enable = true;
    openFirewall = true;
    group = "media";
    webuiPort = 8080;
    torrentingPort = 51413;
    serverConfig = {
      LegalNotice.Accepted = true;
      Preferences = {
        General.Locale = "en";
        WebUI.Username = "admin";
        # Set your password via the web UI on first login (default: adminadmin)
      };
    };
    extraArgs = [ "--confirm-legal-notice" ];
  };

  # ── SSH ─────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };

  # ── Packages ────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    htop
    nfs-utils
  ];

  # ── Nix ─────────────────────────────────────────────
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # ── Firewall ────────────────────────────────────────
  # Individual services open their own ports via openFirewall
  networking.firewall.enable = true;

  # ── State version ───────────────────────────────────
  system.stateVersion = "25.11";
}

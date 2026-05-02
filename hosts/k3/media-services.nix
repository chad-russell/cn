# ── Media Services (k3) ────────────────────────────────────────────
#
# All services run as native NixOS systemd services.
# Shared `media` group (GID 2000) for NFS access.

{ config, lib, pkgs, ... }:

{
  # ── Shared media group ──────────────────────────────────────────
  users.groups.media = { gid = 2000; };
  users.users.crussell.extraGroups = [ "media" ];

  # ── Jellyfin ────────────────────────────────────────────────────
  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };
  users.users.jellyfin.extraGroups = [ "media" ];

  # ── Sonarr ──────────────────────────────────────────────────────
  services.sonarr = {
    enable = true;
    openFirewall = true;
    group = "media";
  };

  # ── Radarr ──────────────────────────────────────────────────────
  services.radarr = {
    enable = true;
    openFirewall = true;
    group = "media";
  };

  # ── Prowlarr ────────────────────────────────────────────────────
  services.prowlarr = {
    enable = true;
    openFirewall = true;
  };
  systemd.services.prowlarr.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "prowlarr";
    Group = "media";
    StateDirectory = "prowlarr";
  };
  users.users.prowlarr = {
    isSystemUser = true;
    group = "media";
    home = "/var/lib/prowlarr";
  };

  # ── Jellyseerr ──────────────────────────────────────────────────
  services.jellyseerr = {
    enable = true;
    openFirewall = true;
    port = 5055;
  };
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

  # ── qBittorrent ─────────────────────────────────────────────────
  services.qbittorrent = {
    enable = true;
    openFirewall = true;
    group = "media";
    webuiPort = 8080;
    torrentingPort = 51413;
    serverConfig = {
      LegalNotice.Accepted = true;
      BitTorrent.Session = {
        DefaultSavePath = "/mnt/media/Downloads";
        TempPath = "/mnt/media/Downloads/incomplete";
      };
      Preferences = {
        General.Locale = "en";
        WebUI.Username = "admin";
        Downloads = {
          SavePath = "/mnt/media/Downloads";
          TempPath = "/mnt/media/Downloads/incomplete";
        };
      };
    };
    extraArgs = [ "--confirm-legal-notice" ];
  };
}

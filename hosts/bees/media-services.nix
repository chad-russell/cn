# ── Media Services (bees) ──────────────────────────────────────────
#
# Jellyfin runs as a podman quadlet (portable); the *arr stack runs as
# native NixOS systemd services. Shared `media` group (GID 2000) for NFS access.

{ config, lib, pkgs, ... }:

{
  # ── Shared media group ──────────────────────────────────────────
  users.groups.media = { gid = 2000; };
  users.users.crussell.extraGroups = [ "media" ];

  # ── Jellyfin (podman quadlet) ───────────────────────────────────
  # Runs as uid 995 (carried over from the native NixOS module) so it reads
  # the existing /var/lib/jellyfin data unchanged. The container binds the
  # same paths the native service used and passes the same jellyfin flags,
  # keeping the library DB and config valid. See hosts/bees/jellyfin.container.
  environment.etc."containers/systemd/jellyfin.container" = {
    source = ./jellyfin.container;
    mode = "0644";
  };
  users.groups.jellyfin = { gid = 994; };
  users.users.jellyfin = {
    uid = 995;
    isSystemUser = true;
    group = "jellyfin";
    extraGroups = [ "media" ];
    home = "/var/lib/jellyfin";
    createHome = false;
  };

  # ── Sonarr (podman quadlet) ─────────────────────────────────────
  # Runs as uid 274 via the linuxserver image's PUID/PGID (PGID = media, 2000),
  # so it reads the existing /var/lib/sonarr/.config/NzbDrone data unchanged.
  # See hosts/bees/sonarr.container.
  environment.etc."containers/systemd/sonarr.container" = {
    source = ./sonarr.container;
    mode = "0644";
  };
  users.users.sonarr = {
    uid = 274;
    isSystemUser = true;
    group = "media";
    home = "/var/lib/sonarr";
    createHome = false;
  };

  # ── Radarr (podman quadlet) ─────────────────────────────────────
  # Runs as uid 275 via the linuxserver image's PUID/PGID (PGID = media, 2000),
  # so it reads the existing /var/lib/radarr/.config/Radarr data unchanged.
  # See hosts/bees/radarr.container.
  environment.etc."containers/systemd/radarr.container" = {
    source = ./radarr.container;
    mode = "0644";
  };
  users.users.radarr = {
    uid = 275;
    isSystemUser = true;
    group = "media";
    home = "/var/lib/radarr";
    createHome = false;
  };

  # ── Prowlarr (podman quadlet) ───────────────────────────────────
  # Runs as uid 993 via the linuxserver image's PUID/PGID (PGID = media, 2000),
  # so it reads the existing /var/lib/prowlarr data unchanged. No /mnt/media
  # mount — Prowlarr is an indexer manager, not a media service.
  # See hosts/bees/prowlarr.container.
  environment.etc."containers/systemd/prowlarr.container" = {
    source = ./prowlarr.container;
    mode = "0644";
  };
  users.users.prowlarr = {
    uid = 993;
    isSystemUser = true;
    group = "media";
    home = "/var/lib/prowlarr";
    createHome = false;
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

  # Open UDP for BitTorrent uTP/DHT — the NixOS module only opens TCP.
}

# ── bees: Backup Configuration ─────────────────────────────────────
#
# Backs up application state and the Immich photo library.
# Immich photos live on the NAS at /mnt/photos (NFS mount).

{ config, lib, pkgs, ... }:

{
  imports = [
    ../../modules/restic-backup.nix
    ../../modules/btrfs-snapshots.nix
  ];

  # ── Restic backups (NAS + S3) ──────────────────────────────────
  services.homelab-backup = {
    enable = true;

    paths = [
      # Application state
      "/var/lib/jellyfin"
      "/var/lib/postgresql"
      "/var/lib/sonarr"
      "/var/lib/radarr"
      "/var/lib/prowlarr"
      "/var/lib/qBittorrent"
      "/var/lib/jellyseerr"
      "/var/lib/ntfy-sh"
      "/var/lib/datenight"
      "/var/lib/redis-immich"

      # Container volumes (Caddy certs, etc.)
      "/var/lib/containers/storage/volumes"

      # Caddy configuration (installed by nix but includes TLS certs)
      "/etc/caddy"

      # Immich photo library (on NAS via NFS)
      "/mnt/photos"
    ];

    exclude = [
      # Don't back up container image layers (pullable from registries)
      "/var/lib/containers/storage/overlay"
      "/var/lib/containers/storage/overlay-images"
      "/var/lib/containers/storage/overlay-layers"
      "/var/lib/containers/storage/imagemanifest"
      "/var/lib/containers/storage/rocm"

      # Jellyfin transcodes and cache
      "/var/lib/jellyfin/transcodes"
      "/var/lib/jellyfin/data/transcodes"
      "/var/lib/jellyfin/log"

      # Immich regeneratable from originals (thumbnails + transcoded videos).
      # Saves ~10 GiB in S3 and speeds restores; Immich rebuilds these on demand.
      "/mnt/photos/thumbs"
      "/mnt/photos/encoded-video"

      # qBittorrent incomplete downloads
      "*.!qB"

      # General caches
      "*.log"
      "*.tmp"
      "*.cache"
    ];
  };

  # ── Btrfs snapshots ────────────────────────────────────────────
  services.btrfs-snapshots = {
    enable = true;
    subvolumes = [ "@" "@home" "@var" "@srv" ];
  };

  # ── Output-layer monitoring: a fresh snapshot must appear daily ──
  # Catches "restic job silently stopped running" (job failure itself is
  # already covered by the restic module's onFailure → ntfy).
  homelab.freshnessChecks.bees-restic = {
    description = "bees restic S3 backup";
    environmentFile = config.age.secrets.restic-s3-credentials.path;
    extraPath = [ pkgs.restic pkgs.jq ];
    checkCommand = ''
      export RESTIC_REPOSITORY="s3:https://s3.${config.services.homelab-backup.s3Region}.amazonaws.com/${config.services.homelab-backup.s3Bucket}/bees"
      export RESTIC_PASSWORD_FILE="${config.age.secrets.restic-password.path}"
      t="$(restic snapshots --json 2>/dev/null | jq -r 'sort_by(.time) | last | .time')"
      [ -n "$t" ] || { echo "no snapshots in S3 repo"; exit 1; }
      ageh=$(( ($(date +%s) - $(date -d "$t" +%s)) / 3600 ))
      echo "newest snapshot is ''${ageh}h old"
      [ "''${ageh}" -lt 36 ]
    '';
  };
}

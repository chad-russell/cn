# ── think: Backup Configuration ────────────────────────────────────
#
# Restic backups (NAS + S3) recovered off the deprecated hod profile.
# Uses the shared services.homelab-backup module (system-level, runs as
# root via systemd timers). Secrets are decrypted by agenix.

{ config, lib, pkgs, username, ... }:

{
  imports = [
    ../modules/restic-backup.nix
    ../modules/btrfs-snapshots.nix
  ];

  # ── Btrfs snapshots ────────────────────────────────────────────
  services.btrfs-snapshots = {
    enable = true;
    subvolumes = [ "@" "@home" ];
  };

  # ── Restic backups (NAS + S3) ──────────────────────────────────
  # The homelab-backup module declares its own age.secrets
  # (restic-password, restic-s3-credentials) using restic-password-<hostname>.age.
  services.homelab-backup = {
    enable = true;

    paths = [
      "/home/${username}/Code"
      "/home/${username}/.config"
      "/home/${username}/.ssh"
    ];

    exclude = [
      "**/node_modules"
      "**/.cache"
      "**/target"
      "**/.local/share/hod"
      "**/.local/share/vicinae"
      "**/dist"
      "**/.next"
      "*.log"
      "*.tmp"
    ];
  };
}

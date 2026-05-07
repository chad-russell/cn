# ── think: Backup Configuration ─────────────────────────────────────
#
# Backs up code repos, config, and SSH keys from the laptop.

{ config, lib, pkgs, username, ... }:

{
  imports = [
    ../modules/restic-backup.nix
    ../modules/btrfs-snapshots.nix
  ];

  # ── Restic backups (NAS + S3) ──────────────────────────────────
  services.homelab-backup = {
    enable = true;

    paths = [
      "/home/${username}/Code"
      "/home/${username}/.config"
      "/home/${username}/.ssh"
    ];

    exclude = [
      # Large caches / rebuildable state
      "**/node_modules"
      "**/.cache"
      "**/target"           # Rust build artifacts
      "**/.local/share/hod"
      "**/.local/share/vicinae"
      "**/dist"
      "**/.next"
      "*.log"
      "*.tmp"
    ];
  };

  # ── Btrfs snapshots ────────────────────────────────────────────
  services.btrfs-snapshots = {
    enable = true;
    subvolumes = [ "@" "@home" ];
  };
}

# ── bee: Backup Configuration ──────────────────────────────────────
#
# Backs up the Gloo dev stack and buildspace data.

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
      "/home/crussell/Gloo"
      "/home/crussell/buildspace"
    ];

    exclude = [
      # Node modules (rebuildable)
      "**/node_modules"
      ".npm"
      "*.log"
      "*.tmp"
    ];
  };

  # ── Btrfs snapshots ────────────────────────────────────────────
  services.btrfs-snapshots = {
    enable = true;
    subvolumes = [ "@" "@home" "@srv" ];
  };
}

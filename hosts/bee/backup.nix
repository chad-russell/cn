# ── bee: Backup Configuration ──────────────────────────────────────
#
# Backs up the Gloo dev stack data and the Hermes Agent state
# (sessions, mem0/qdrant vectors, MEMORY.md, skills, cron).

{ config, lib, pkgs, ... }:

{
  imports =
    [ ../../modules/restic-backup.nix ../../modules/btrfs-snapshots.nix ];

  # ── Restic backups (NAS + S3) ──────────────────────────────────
  services.homelab-backup = {
    enable = true;

    paths = [
      "/home/crussell/Gloo"

      # Hermes Agent state: sessions, mem0/qdrant vectors, MEMORY.md,
      # skills, plugins, cron jobs. This is the agent's entire memory
      # and config — irreplaceable if the host is lost.
      "/var/lib/hermes"

      # Glen's personal brain: timestamped event log + inbox drops
      # (~/brain, 2026-09-05). Git-tracked locally; this adds a second
      # copy beyond the checkout.
      "/home/crussell/brain"
      # Stoat instance: compose project + config (secrets.env lives here —
      # restic-encrypted at rest on S3, acceptable for a personal instance;
      # volumes live in ~/.local/share/containers, covered below)
      "/home/crussell/stoat"
      # glen agent state: memory log, session logs, skills git repo,
      # stoat channel state (node_modules excluded by the global rule)
      "/var/lib/dsh"
      # glen curated source repo (no git remote — restic is its off-box copy)
      "/home/crussell/glen"
      # buzz relay deploy config + secrets (.env 0600; volumes in containers storage)
      "/home/crussell/buzz"
      # rootless podman storage: stoat named volumes (db, minio, rabbit, caddy)
      "/home/crussell/.local/share/containers"
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

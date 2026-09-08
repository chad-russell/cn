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
    ];

    exclude = [
      # Node modules (rebuildable)
      "**/node_modules"
      ".npm"
      "*.log"
      "*.tmp"

      # HML-4: Hermes checkpoint store + quick state snapshots.
      # Upstream's own backup code excludes these exact dirs from
      # `hermes backup` (hermes_cli/backup.py _EXCLUDED_DIRS):
      # checkpoints are turn-scoped rollback caches ("regenerated,
      # don't port"), and every state-snapshot carries a full copy of
      # state.db whose LIVE file this backup already captures directly.
      # Measured in NAS snapshot 0511a260 (2026-09-08): checkpoints
      # 653 MiB + state-snapshots 499 MiB = ~1.13 GiB re-uploaded into
      # every nightly snapshot on both repos (NAS keep-daily 30, S3
      # 30 daily + 12 monthly). Retention (ae09257) bounds on-disk
      # growth; this stops the redundant offsite copies.
      "/var/lib/hermes/.hermes/checkpoints"
      "/var/lib/hermes/.hermes/state-snapshots"
    ];
  };

  # ── Btrfs snapshots ────────────────────────────────────────────
  services.btrfs-snapshots = {
    enable = true;
    subvolumes = [ "@" "@home" "@srv" ];
  };
}

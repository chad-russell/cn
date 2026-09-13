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

      # glen agent state (dsh): memory log, session logs, skills git repo,
      # presets + profile incl. the hand-maintained @glen plugin sources
      # and vendored dsh-relay under profiles/glen/node_modules — edited
      # directly in place (staging repo ~/glen retired 2026-09-13).
      # /var/lib/dsh is also a local git repo for the hand-maintained
      # subset (no remote); THIS backup remains its off-machine copy.
      "/var/lib/dsh"

      # buzz relay deploy config + secrets (.env 0600; volumes in containers storage)
      "/home/crussell/buzz"
      "/home/crussell/.local/share/containers"
    ];

    exclude = [
      # Home-dir node modules (rebuildable). Deliberately NOT a blanket
      # pattern: /var/lib/dsh/profiles/glen/node_modules holds the only
      # copies of the @glen plugin sources + vendored dsh-relay — those
      # must be backed up.
      "/home/crussell/**/node_modules"
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

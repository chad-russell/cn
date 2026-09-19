# ── bee: Backup Configuration ──────────────────────────────────────
#
# Backs up the Gloo dev stack data and the Hermes Agent state
# (sessions, mem0/qdrant vectors, MEMORY.md, skills, cron).

{ ... }:

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

      # glen agent state (dsh): memory log, session logs, skills,
      # presets + profiles incl. the hand-maintained @glen plugin sources,
      # vendored dsh-relay, the acp-* agent profiles — edited directly in place.
      # /var/lib/dsh is also a local git repo for the hand-maintained
      # subset (no remote); THIS backup remains its off-machine copy.
      "/var/lib/dsh"

      # Published artifacts (keep-forever, served by artifacts-server).
      # Added 2026-09-19 (D-015) — cn AGENTS.md had claimed this for a
      # while, but the path was never actually listed until now.
      "/home/crussell/artifacts"

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

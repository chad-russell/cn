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
      # Podman IMAGE layers under the rootless storage root — re-pullable,
      # and the hindsight full image alone is ~9 GB (would re-upload into
      # every nightly NAS+S3 snapshot on each image update). Named VOLUMES
      # (.../storage/volumes, incl. hindsight's pg0 data) do NOT match this
      # pattern and stay backed up.
      "/home/crussell/.local/share/containers/storage/overlay*"

      # Home-dir node modules (rebuildable). Deliberately NOT a blanket
      # pattern: /var/lib/dsh/profiles/glen/node_modules holds the only
      # copies of the @glen plugin sources + vendored dsh-relay — those
      # must be backed up.
      "/home/crussell/**/node_modules"
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

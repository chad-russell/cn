# ── Btrfs Snapshot Timer ─────────────────────────────────────────────
#
# Takes daily read-only snapshots of specified btrfs subvolumes and
# prunes old ones.  Snapshots are stored alongside the live subvolume
# under .snapshots/<subvol-name>/ as btrfs send/receive targets are
# NOT used — snapshots live on the same filesystem for fast local
# rollback only (not a backup).
#
# Usage (per-host):
#
#   services.btrfs-snapshots = {
#     enable = true;
#     subvolumes = [ "@" "@home" "@var" ];
#     keepDaily = 30;
#   };

{ config, lib, pkgs, ... }:

let
  cfg = config.services.btrfs-snapshots;
  btrfsProgs = pkgs.btrfs-progs;

  # Snapshot a subvolume by path, relative to the btrfs top-level
  # subvolume (subvolid=5), via a temporary mount.
  takeSnapshot = pkgs.writeShellScript "btrfs-take-snapshot" ''
    set -euo pipefail

    SUBVOL_NAME="$1"
    # The top-level subvolume is mounted at a known path we'll discover
    # by finding the btrfs device and mounting it temporarily
    DEVICE="$2"
    TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)

    # Use a temporary mount of the top-level subvolume
    TMPDIR=$(mktemp -d)
    trap "umount $TMPDIR && rmdir $TMPDIR" EXIT

    mount -o subvolid=5 "$DEVICE" "$TMPDIR"

    # Ensure snapshot directory exists
    mkdir -p "$TMPDIR/.snapshots/$SUBVOL_NAME"

    # Take read-only snapshot of the live subvolume
    ${btrfsProgs}/bin/btrfs subvolume snapshot -r "$TMPDIR/$SUBVOL_NAME" "$TMPDIR/.snapshots/$SUBVOL_NAME/$TIMESTAMP"

    echo "Snapshot created: .snapshots/$SUBVOL_NAME/$TIMESTAMP"
  '';

  # Prune old snapshots, keeping N daily
  pruneSnapshots = pkgs.writeShellScript "btrfs-prune-snapshots" ''
    set -euo pipefail

    SUBVOL_NAME="$1"
    DEVICE="$2"
    KEEP_DAILY="$3"

    TMPDIR=$(mktemp -d)
    trap "umount $TMPDIR && rmdir $TMPDIR" EXIT

    mount -o subvolid=5 "$DEVICE" "$TMPDIR"

    SNAPDIR="$TMPDIR/.snapshots/$SUBVOL_NAME"
    if [ ! -d "$SNAPDIR" ]; then
      echo "No snapshots directory for $SUBVOL_NAME, skipping prune"
      exit 0
    fi

    # List snapshots newest-first, delete everything beyond KEEP_DAILY
    SNAPSHOTS=$(ls -1r "$SNAPDIR" 2>/dev/null || true)

    TOTAL=$(echo "$SNAPSHOTS" | grep -c . || true)
    if [ "$TOTAL" -le "$KEEP_DAILY" ]; then
      echo "Only $TOTAL snapshots for $SUBVOL_NAME, nothing to prune"
      exit 0
    fi

    echo "$SNAPSHOTS" | tail -n +"$((KEEP_DAILY + 1))" | while read -r snap; do
      if [ -n "$snap" ] && [ -d "$SNAPDIR/$snap" ]; then
        echo "Deleting old snapshot: $SUBVOL_NAME/$snap"
        ${btrfsProgs}/bin/btrfs subvolume delete "$SNAPDIR/$snap"
      fi
    done
  '';

  # Combined script for all subvolumes. Failures PROPAGATE: a subvolume
  # that fails to snapshot or prune increments FAILED and the run exits
  # non-zero at the end, so the service enters "failed" and (where the
  # host provides the template) OnFailure alerts fire. The old
  # `|| echo "WARNING"` form swallowed every failure — the local rollback
  # layer could stop for weeks with exit 0 and nothing watching.
  snapshotAll = pkgs.writeShellScript "btrfs-snapshot-all" ''
    set -euo pipefail

    DEVICE="$1"
    KEEP_DAILY="$2"
    shift 2
    SUBVOLUMES=("$@")

    echo "=== btrfs snapshot run: $(date) ==="
    FAILED=0

    for subvol in "''${SUBVOLUMES[@]}"; do
      echo "--- Snapshotting $subvol ---"
      if ! ${takeSnapshot} "$subvol" "$DEVICE"; then
        echo "ERROR: Failed to snapshot $subvol" >&2
        FAILED=$((FAILED + 1))
        continue
      fi
      echo "--- Pruning $subvol (keeping $KEEP_DAILY daily) ---"
      if ! ${pruneSnapshots} "$subvol" "$DEVICE" "$KEEP_DAILY"; then
        echo "ERROR: Failed to prune $subvol" >&2
        FAILED=$((FAILED + 1))
      fi
    done

    echo "=== btrfs snapshot run complete ($FAILED failures) ==="
    [ "$FAILED" -eq 0 ]
  '';

in {
  options.services.btrfs-snapshots = {
    enable = lib.mkEnableOption "btrfs snapshot timer";

    subvolumes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        List of btrfs subvolume names to snapshot (e.g. [ "@" "@home" "@var" ]).
        The subvolume name is the path relative to the top-level subvolume.
      '';
      example = [ "@" "@home" "@var" ];
    };

    device = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        The btrfs device (partition) to mount for snapshot operations.
        If null, will be auto-detected from the root filesystem.
      '';
      example = "/dev/nvme0n1p3";
    };

    keepDaily = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Number of daily snapshots to retain.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = cfg.subvolumes != [ ];
      message = "btrfs-snapshots: at least one subvolume must be specified";
    }];

    # Auto-detect device if not specified
    services.btrfs-snapshots.device = lib.mkDefault
      (let rootFs = config.fileSystems."/" or null;
      in if rootFs != null then rootFs.device else null);

    systemd.services.btrfs-snapshots = {
      description = "Btrfs Snapshot & Prune";
      # Alert on failure where the host provides the freshness-checks
      # ntfy-failure@ template (bees/nas do); absent elsewhere, the
      # dependency is simply skipped.
      onFailure =
        lib.optionals (config.systemd.units ? "ntfy-failure@.service")
          [ "ntfy-failure@btrfs-snapshots.service" ];
      path = [ btrfsProgs pkgs.util-linux ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${snapshotAll} ${cfg.device} ${toString cfg.keepDaily} ${
            lib.concatStringsSep " " cfg.subvolumes
          }";
      };
    };

    systemd.timers.btrfs-snapshots = {
      description = "Daily btrfs snapshots";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "30min";
      };
    };
  };
}

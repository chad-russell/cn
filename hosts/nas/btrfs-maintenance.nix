# ── nas: Btrfs Maintenance ────────────────────────────────────────
#
# Monthly scrub: reads every block, verifies checksums, repairs
# from mirror if corruption found. Critical for long-term data health.
# Runs the first Sunday of each month at 03:00.
#
# Both jobs alert on failure via the ntfy-failure@ template (nas
# imports freshness-checks): detected corruption or a dead job is a
# page, not a journal line — these two are the pool's only integrity
# checks.

{ config, lib, pkgs, ... }:

{
  # Monthly btrfs scrub on the data pool
  systemd.services.btrfs-scrub = {
    description = "Btrfs scrub on data pool";
    onFailure = [ "ntfy-failure@btrfs-scrub.service" ];
    path = with pkgs; [ btrfs-progs ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.btrfs-progs}/bin/btrfs scrub start -Bd /pool/media";
      # -B: run in foreground (wait for completion)
      # -d: print device stats
      IOSchedulingClass = "idle";
      Nice = 19;
    };
  };

  systemd.timers.btrfs-scrub = {
    description = "Monthly btrfs scrub on data pool";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-01..07 03:00:00";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  # Balance check — reclaims unused chunk space quarterly
  systemd.services.btrfs-balance = {
    description = "Btrfs balance on data pool";
    onFailure = [ "ntfy-failure@btrfs-balance.service" ];
    path = with pkgs; [ btrfs-progs ];
    serviceConfig = {
      Type = "oneshot";
      # Only re-locate chunks that are less than 10% utilized
      ExecStart =
        "${pkgs.btrfs-progs}/bin/btrfs balance start -dusage=10 -musage=10 /pool/media";
      IOSchedulingClass = "idle";
      Nice = 19;
    };
  };

  systemd.timers.btrfs-balance = {
    # Quarterly on the 1st of Jan/Apr/Jul/Oct. The old "Sun *-*-01"
    # required the 1st to ALSO be a Sunday — it fired roughly every
    # 7 months instead of quarterly.
    description = "Quarterly btrfs balance on data pool";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-1,4,7,10-01 04:00:00";
      Persistent = true;
      RandomizedDelaySec = "2h";
    };
  };
}

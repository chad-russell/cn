# ── bees: pull nightly Forgejo dumps from gateway, into restic scope ─
#
# gateway (git.crussell.io) is a small Hetzner VPS that must stay
# secret-free: it creates `forgejo dump` zips nightly (gateway's
# forgejo-dump-bounded.nix) but has no restic/S3 credentials. bees pulls
# them over Nebula via rsync-over-ssh so the dumps land on a restic-covered
# path — the backup job (backup.nix allowlist) then ships them to NAS + S3
# with everything else.
#
# Runs as root (rsync writes root-owned files under /var/lib/forgejo-dumps)
# using crussell's ed25519 key, which is already an authorized root key on
# gateway. gateway's host key is pinned declaratively (no TOFU), matching
# what /root/.ssh/known_hosts on bees already trusts.

{ config, lib, pkgs, ... }:

let
  dumpDir = "/var/lib/forgejo-dumps";
  src = "root@10.10.0.2:/var/lib/forgejo/dump-temp/";
in {
  # gateway's host key (ssh-keyscan 10.10.0.2, matches bees root's
  # known_hosts) — pinned so the root pull unit never needs TOFU prompts.
  programs.ssh.knownHosts.gateway-nebula = {
    hostNames = [ "10.10.0.2" ];
    publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAk49Sp8/Tb9lZLmDlGNAvkb5CbTmy3gVYzwzCa+Nwee";
  };

  systemd.services.forgejo-dump-pull = {
    description =
      "Pull Forgejo dumps from gateway into restic-covered ${dumpDir}";
    # 03:30 gateway dump + ~1 min runtime → pull at 04:45 latest start.
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    path = [ pkgs.openssh pkgs.rsync pkgs.coreutils ];
    script = ''
      set -euo pipefail
      mkdir -p ${dumpDir}

      # -a archive, --delete mirrors gateway's retain-3 prune, --times lets
      # subsequent runs skip unchanged files. --no-owner/--no-group: without
      # them rsync copies gateway's numeric forgejo uid/gid, which maps to an
      # unrelated user on bees (prowlarr) — files must land root-owned here.
      # crussell's key is already an authorized root key on gateway (it's
      # how deploys reach the VPS).
      rsync -a --delete --times --no-owner --no-group \
        -e "ssh -i /home/crussell/.ssh/id_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes" \
        ${src} ${dumpDir}/

      echo "dumps on bees:"
      ls -l ${dumpDir}
    '';
    onFailure = [ "ntfy-failure@forgejo-dump-pull.service" ];
  };

  systemd.timers.forgejo-dump-pull = {
    description = "Nightly pull of Forgejo dumps from gateway";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:45:00";
      Persistent = true;
      # Small safety margin over 03:30+duration in case the VPS dump runs long.
      RandomizedDelaySec = "10m";
    };
  };

  # ── Output-layer monitoring: pulled dumps must stay fresh ────────
  # Covers BOTH legs of the pipeline: a gateway dump that silently stops
  # producing zips OR a dead/disabled pull timer both leave stale files
  # here → ntfy (the silent-staleness class modules/freshness-checks.nix
  # exists for). That makes a gateway-side dump-temp check redundant.
  homelab.freshnessChecks.forgejo-dumps = {
    description = "Forgejo dumps pulled from gateway";
    path = dumpDir;
    glob = "forgejo-dump-*.zip";
    # Pull lands ~04:45–04:55 nightly; the check runs daily ~00:00 (+30m
    # jitter) when the newest zip is ~19h old. One missed pull → ~43h →
    # alert. A Persistent catch-up run after a ~1-day outage stays < 40h.
    maxAgeHours = 40;
  };
}

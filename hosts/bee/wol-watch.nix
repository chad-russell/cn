# ── WoL watcher: wake bees/nas when they go dark ───────────────────
#
# 2026-09-08 power outage: bees + nas lost wall power ~12:00 and sat
# off until Chad pressed their power buttons. bee (and HAOS) ride a
# different circuit and survived, so bee is the wake origin: every 2 min
# ping bees/nas LAN IPs; 3 consecutive misses (≥6 min, above a normal
# reboot window) → send a magic packet to every NIC of the target.
#
# Pairs with modules/wol-enable.nix (target half, deployed on
# bees/nas). BIOS "restore AC power loss = on" — once set by hand — is
# the primary mechanism for power-return boots; this watcher also covers
# shutdowns/hangs the BIOS setting can't.
#
# Trade-off to know: a deliberately powered-off bees/nas will be woken
# back up ~6 min later. Stop this timer first when a host must stay
# down: `systemctl stop wol-watch.timer`.

{ lib, pkgs, ... }:

let
  # MACs pinned 2026-09-08 (stable — burned into the NICs).
  # bees: Intel E610 pair; nas: Intel I226-V pair. Both ports per host
  # so the wake works regardless of which port carries the link.
  targets = [
    {
      name = "bees";
      ip = "192.168.20.41";
      macs = [
        "78:55:36:02:ce:be" # enp196s0f0 (idle)
        "78:55:36:02:ce:bf" # enp196s0f1 (active)
      ];
    }
    {
      name = "nas";
      ip = "192.168.20.31";
      macs = [
        "6c:1f:f7:3f:d5:19" # enp2s0 (idle)
        "6c:1f:f7:3f:d5:1a" # enp3s0 (active)
      ];
    }
  ];

  checkCalls = lib.concatStrings (map (t: ''
    check_target ${t.name} ${t.ip} ${lib.concatStringsSep " " t.macs}
  '') targets);
in {
  systemd.services.wol-watch = {
    description = "Wake bees/nas via WoL after 3 missed pings";
    path = [ pkgs.iputils pkgs.wol ];
    script = ''
      set -u
      STATE=/var/lib/wol-watch
      mkdir -p "$STATE"

      check_target() {
        local name="$1" ip="$2"; shift 2
        local file="$STATE/$name.miss"
        if ping -c 1 -W 3 "$ip" >/dev/null 2>&1; then
          if [ -f "$file" ]; then
            echo "wol-watch: $name ($ip) reachable again — clearing miss counter"
            rm -f "$file"
          fi
          return 0
        fi
        local miss
        miss=$(cat "$file" 2>/dev/null || echo 0)
        miss=$((miss + 1))
        echo "$miss" > "$file"
        echo "wol-watch: $name ($ip) missed $miss/3"
        if [ "$miss" -ge 3 ]; then
          for mac in "$@"; do
            if wol -i 192.168.20.255 "$mac"; then
              echo "wol-watch: sent magic packet → $name ($mac)"
            else
              echo "wol-watch: wol send FAILED for $name ($mac)" >&2
            fi
          done
        fi
      }

      ${checkCalls}
      exit 0
    '';
  };

  systemd.timers.wol-watch = {
    description = "Ping bees/nas every 2 min; WoL-wake after 3 misses";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitActiveSec = "2min";
      AccuracySec = "30s";
    };
  };
}

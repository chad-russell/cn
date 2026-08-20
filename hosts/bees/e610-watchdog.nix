# ── bees: E610 NIC link watchdog ────────────────────────────────────
#
# The on-board Intel E610-XT2 (enp196s0f1) has a known firmware bug
# (NVM 1.16 and earlier; see Intel community "E610 Firmware Recovery
# Mode Under Load"): under heavy PCIe/GPU load the NIC can enter
# firmware recovery mode and drop carrier permanently — the host stays
# up but is unreachable at L2 until a power-cycle. First observed
# 2026-08-20 (17-day-old boot, llama-server inference load).
#
# This watchdog cannot fix a full fw-recovery lockout (that needs
# power), but it:
#   1. detects network death within minutes
#   2. bounces the link (recovers transient ixgbe wedges)
#   3. reboots ONCE per outage episode — a warm reboot re-enumerates
#      PCIe, which can clear fw-recovery in the less severe cases
#   4. never reboots twice for the same episode (prevents loops; if
#      the reboot doesn't recover it, a human power-cycle is needed —
#      the Hermes-side health check alerts Telegram either way)
#
# Cadence: every 2 min (via OnUnitActiveSec), first run 5 min after
# boot (grace for link-up + nebula handshake).
{ config, lib, pkgs, ... }:

{
  systemd.services.e610-link-watchdog = {
    description = "E610 NIC link watchdog: bounce link / reboot on network death";
    # Best-effort: never block shutdown/reboot
    wantedBy = [ ];
    serviceConfig = {
      Type = "oneshot";
    };
    path = with pkgs; [ iputils iproute2 coreutils systemd ];
    script = ''
      IFACE="enp196s0f1"
      STATE=/var/lib/e610-watchdog
      mkdir -p "$STATE"
      FAILS="$STATE/failures"
      EPISODE="$STATE/rebooted-boot-id"

      # ── Boot grace: first 5 minutes after boot, link may still be ──
      # ── coming up (and this timer's first run is OnBootSec=5min)  ──
      UPTIME=$(cut -d. -f1 /proc/uptime)
      [ "$UPTIME" -lt 240 ] && exit 0

      # ── Administratively down = human maintenance, not a failure ──
      OPERSTATE=$(cat /sys/class/net/$IFACE/operstate 2>/dev/null || echo missing)
      [ "$OPERSTATE" = "down" ] && exit 0

      # ── Probe: L3 through the physical NIC only (-I). Two targets, ──
      # ── router + nas on the same L2. Either answering = healthy.  ──
      if ping -c 2 -W 2 -I "$IFACE" 192.168.20.1 >/dev/null 2>&1 \
      || ping -c 2 -W 2 -I "$IFACE" 192.168.20.31 >/dev/null 2>&1; then
        if [ -f "$FAILS" ] && [ "$(cat "$FAILS" 2>/dev/null || echo 0)" -ge 3 ]; then
          echo "e610-watchdog: network RECOVERED (was at $(cat "$FAILS") failures) — clearing episode state"
          logger -t e610-watchdog "network recovered after $(cat "$FAILS") failures"
        fi
      echo 0 > "$FAILS"
        rm -f "$EPISODE"
        exit 0
      fi

      FAILCOUNT=$(( $(cat "$FAILS" 2>/dev/null || echo 0) + 1 ))
      echo "$FAILCOUNT" > "$FAILS"
      echo "e610-watchdog: no L3 via $IFACE (failure #$FAILCOUNT, operstate=$OPERSTATE)"

      if [ "$FAILCOUNT" -eq 5 ]; then
        # Transient ixgbe wedge? Bounce the link once.
        echo "e610-watchdog: bouncing $IFACE (5 consecutive failures)"
        logger -t e610-watchdog "bouncing $IFACE after 5 failures"
        ip link set "$IFACE" down
        sleep 3
        ip link set "$IFACE" up
        exit 0
      fi

      if [ "$FAILCOUNT" -ge 10 ]; then
        # One reboot per outage episode. If we already rebooted for
        # this boot-id's episode and the network is STILL dead, a warm
        # reboot doesn't clear it — give up (human power-cycle needed).
        BOOTID=$(cat /proc/sys/kernel/random/boot_id)
        if [ -f "$EPISODE" ] && [ "$(cat "$EPISODE")" = "$BOOTID" ]; then
          echo "e610-watchdog: already rebooted this episode ($BOOTID) and network is still dead — giving up, needs power-cycle"
          logger -t e610-watchdog "REBOOT DID NOT RECOVER — needs power-cycle"
          exit 0
        fi
        echo "e610-watchdog: 10 consecutive failures — rebooting to re-enumerate PCIe (one attempt)"
        echo "$BOOTID" > "$EPISODE"
        sync
        logger -t e610-watchdog "rebooting after 10 network failures"
        systemctl reboot
      fi
    '';
  };

  systemd.timers.e610-link-watchdog = {
    description = "E610 NIC link watchdog (every 2 min)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "2min";
      AccuracySec = "30s";
    };
  };
}

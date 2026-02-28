{ config, pkgs, ... }:

{
  # Network interface optimizations (equivalent to ethtool commands)
  # Disable various offloading features for better performance/stability
  boot.kernelParams = [
    # Disable GSO (Generic Segmentation Offload)
    # "net.ifnames=0" # Removed to avoid interface renaming conflicts with eno1 config
  ];

  # Kernel network buffer tuning to reduce RX drops under load
  boot.kernel.sysctl = {
    "net.core.netdev_max_backlog" = 16384;
    "net.core.rmem_max" = 134217728;
    "net.core.wmem_max" = 134217728;
    "net.core.rmem_default" = 262144;
    "net.core.wmem_default" = 262144;
  };

  # Apply ethtool optimizations via systemd service
  # This runs once at boot and applies network interface optimizations
  systemd.services.ethtool-optimizations = {
    description = "Apply ethtool optimizations to network interface";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig = {
      ConditionPathExists = "/sys/class/net/eno1";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "ethtool-optimizations" ''
        set -euo pipefail
        # Wait for interface to be up
        for _ in $(seq 1 30); do
          state=$(cat /sys/class/net/eno1/operstate 2>/dev/null || true)
          [ "$state" = "up" ] && break
          sleep 1
        done

        echo "[ethtool-optimizations] operstate: $(cat /sys/class/net/eno1/operstate 2>/dev/null || echo unknown)"

        # Apply ethtool optimizations
        ${pkgs.ethtool}/bin/ethtool -K eno1 gso off gro off tso off tx off rx off rxvlan off txvlan off sg off || true

        # Disable Energy Efficient Ethernet (EEE) if supported
        ${pkgs.ethtool}/bin/ethtool --set-eee eno1 eee off || true

        # Interrupt coalescing to reduce RX pressure (tune if needed)
        ${pkgs.ethtool}/bin/ethtool -C eno1 rx-usecs 250 rx-frames 256 tx-usecs 250 tx-frames 256 || true

        # Increase ring buffers to driver max to reduce RX drops
        max_rx=$(${pkgs.ethtool}/bin/ethtool -g eno1 2>/dev/null | ${pkgs.gawk}/bin/awk '
          /Pre-set maximums:/ {section=1; next}
          /Current hardware settings:/ {section=0}
          section && $1 == "RX:" {print $2}
        ')
        max_tx=$(${pkgs.ethtool}/bin/ethtool -g eno1 2>/dev/null | ${pkgs.gawk}/bin/awk '
          /Pre-set maximums:/ {section=1; next}
          /Current hardware settings:/ {section=0}
          section && $1 == "TX:" {print $2}
        ')

        if [ -n "$max_rx" ] && [ -n "$max_tx" ]; then
          ${pkgs.ethtool}/bin/ethtool -G eno1 rx "$max_rx" tx "$max_tx" || true
        fi

        echo "[ethtool-optimizations] ring:"
        ${pkgs.ethtool}/bin/ethtool -g eno1 || true
      '';
      RemainAfterExit = true;
    };
  };

  systemd.services.ethtool-drop-monitor = {
    description = "Log RX drop/miss deltas for eno1";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig = {
      ConditionPathExists = "/sys/class/net/eno1";
    };
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "ethtool-drop-monitor";
      ExecStart = pkgs.writeShellScript "ethtool-drop-monitor" ''
        set -euo pipefail

        state_dir="/var/lib/ethtool-drop-monitor"
        prev_file="$state_dir/prev"

        rx_dropped=$(cat /sys/class/net/eno1/statistics/rx_dropped || echo 0)
        rx_missed=$(cat /sys/class/net/eno1/statistics/rx_missed_errors || echo 0)
        rx_no_buffer=$(cat /sys/class/net/eno1/statistics/rx_no_buffer_count || echo 0)

        if [ -f "$prev_file" ]; then
          read -r prev_dropped prev_missed prev_no_buffer < "$prev_file" || true
        else
          prev_dropped=0
          prev_missed=0
          prev_no_buffer=0
        fi

        delta_dropped=$((rx_dropped - prev_dropped))
        delta_missed=$((rx_missed - prev_missed))
        delta_no_buffer=$((rx_no_buffer - prev_no_buffer))

        echo "rx_dropped=$rx_dropped (+$delta_dropped) rx_missed=$rx_missed (+$delta_missed) rx_no_buffer=$rx_no_buffer (+$delta_no_buffer)"

        printf "%s %s %s\n" "$rx_dropped" "$rx_missed" "$rx_no_buffer" > "$prev_file"
      '';
    };
  };

  systemd.timers.ethtool-drop-monitor = {
    description = "Periodic RX drop/miss delta logging for eno1";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "1m";
      Unit = "ethtool-drop-monitor.service";
    };
  };
}

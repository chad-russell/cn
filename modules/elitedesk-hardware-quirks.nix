# ── Elitedesk 800 G3 Hardware Quirks ───────────────────────────────
#
# The Intel I219-LM NIC on EliteDesk 800 G3 is notorious for
# "Detected Hardware Unit Hang" errors under high packet loads.
# This module applies all known workarounds.

{ config, lib, pkgs, ... }:

{
  # ── Kernel params: prevent PCIe power management issues ──────────
  boot.kernelParams = [
    "pcie_aspm=off"                          # Force PCIe link fully powered
    "e1000e.SmartPowerDownRxPacket=0"        # Disable NIC smart power down
    "e1000e.SmartPowerDown=0"
  ];

  # ── Network buffer tuning ────────────────────────────────────────
  boot.kernel.sysctl = {
    "net.core.netdev_max_backlog" = 16384;
    "net.core.rmem_max" = 134217728;
    "net.core.wmem_max" = 134217728;
    "net.core.rmem_default" = 262144;
    "net.core.wmem_default" = 262144;
  };

  # ── Disable NIC offloading on boot ───────────────────────────────
  systemd.services.fix-e1000e-offload = {
    description = "Disable NIC offloading to fix e1000e hangs on EliteDesk 800 G3";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${lib.getExe pkgs.ethtool} -K eno1 tso off gso off gro off sg off tx off rx off || true
      ${lib.getExe pkgs.ethtool} --set-eee eno1 eee off || true
    '';
  };

  # ── Hardware watchdog ────────────────────────────────────────────
  boot.kernelModules = [ "iTCO_wdt" ];
  systemd.watchdog.runtimeTime = "30s";
  systemd.watchdog.rebootTime = "2min";
}

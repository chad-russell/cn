{ config, pkgs, ... }:

{
  # EliteDesk 800 G3 Intel I219-LM NIC fixes
  # This module addresses the notorious "Detected Hardware Unit Hang" error
  # that occurs with the e1000e driver under high packet loads (Kubernetes, etc.)

  # 1. Kernel boot parameters to prevent PCIe power management issues
  boot.kernelParams = [
    # Force PCIe link to stay fully powered, preventing NIC low-power state crashes
    "pcie_aspm=off"
    # Disable Intel e1000e "Smart Power Down" features that cause hangs
    "e1000e.SmartPowerDownRxPacket=0"
    "e1000e.SmartPowerDown=0"
  ];

  # 2. Systemd service to disable NIC hardware offloading features
  # These offloading features (especially scatter-gather) are known to crash
  # the I219-LM buffer management under distributed systems workloads
  systemd.services.fix-e1000e-offload = {
    description = "Disable NIC offloading to fix e1000e hangs on EliteDesk 800 G3";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    # Disable all problematic offloading features:
    # - tso: TCP Segmentation Offload
    # - gso: Generic Segmentation Offload
    # - gro: Generic Receive Offload
    # - sg: Scatter-Gather (critical - often missed but causes crashes)
    # - tx/rx: Hardware checksumming (slightly increases CPU usage but prevents hangs)
    script = ''
      ${pkgs.ethtool}/bin/ethtool -K eno1 tso off gso off gro off sg off tx off rx off
      ${pkgs.ethtool}/bin/ethtool --set-eee eno1 eee off
    '';
  };
}


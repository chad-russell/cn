{ config, pkgs, ... }:

{
  # Network interface optimizations (equivalent to ethtool commands)
  # Disable various offloading features for better performance/stability
  boot.kernelParams = [
    # Disable GSO (Generic Segmentation Offload)
    "net.ifnames=0"
  ];

  # Apply ethtool optimizations via systemd service
  # This runs once at boot and applies network interface optimizations
  systemd.services.ethtool-optimizations = {
    description = "Apply ethtool optimizations to network interface";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "ethtool-optimizations" ''
        # Wait for interface to be up
        sleep 5
        # Apply ethtool optimizations
        ${pkgs.ethtool}/bin/ethtool -K eno1 gso off gro off tso off tx off rx off rxvlan off txvlan off sg off
      '';
      RemainAfterExit = true;
    };
  };
}


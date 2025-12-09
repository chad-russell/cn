{ config, pkgs, lib, ... }:

{
  options = {
    customNetworking.staticIP = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Static IP address for ethernet interface. If null, uses DHCP.";
    };
  };

  config = {
    # Enable systemd-networkd for network management
    systemd.network.enable = true;
    networking.useDHCP = lib.mkIf (config.customNetworking.staticIP == null) true;
    
    # Don't wait for network to be fully configured at boot (prevents timeouts)
    systemd.services.systemd-networkd-wait-online.serviceConfig.ExecStart = [
      "" # clear the default
      "${pkgs.systemd}/lib/systemd/systemd-networkd-wait-online --any"
    ];

    # Configure network interface
    systemd.network.networks."10-lan" = lib.mkIf (config.customNetworking.staticIP != null) {
      matchConfig.Name = "en*";
      networkConfig.DHCP = "no";
      address = [ "${config.customNetworking.staticIP}/24" ];
      routes = [
        { Gateway = "192.168.20.1"; }
      ];
      dns = [ "8.8.8.8" "1.1.1.1" ];
    };

    # Enable the OpenSSH server
    services.openssh.enable = true;
    services.openssh.settings.PermitRootLogin = "prohibit-password";
  };
}

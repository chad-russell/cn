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
    networking.useNetworkd = true;
    networking.useDHCP = false;
    
    # Don't wait for network to be fully configured at boot (prevents timeouts)
    systemd.network.wait-online.anyInterface = true;

    # Configure network interface - either static or DHCP
    systemd.network.networks."10-lan" = {
      matchConfig.Name = "en*";
      networkConfig.DHCP = if (config.customNetworking.staticIP == null) then "yes" else "no";
      address = lib.mkIf (config.customNetworking.staticIP != null) [ "${config.customNetworking.staticIP}/24" ];
      routes = lib.mkIf (config.customNetworking.staticIP != null) [
        { Gateway = "192.168.20.1"; }
      ];
      dns = lib.mkIf (config.customNetworking.staticIP != null) [ "8.8.8.8" "1.1.1.1" ];
    };

    # Enable the OpenSSH server
    services.openssh.enable = true;
    services.openssh.settings.PermitRootLogin = "prohibit-password";
  };
}

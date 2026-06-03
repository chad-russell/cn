{ config, lib, pkgs, ... }:

{
  services.tailscale = {
    enable = true;
  };

  # Allow the tunnel interface to be used for routing
  networking.firewall.checkReversePath = "loose";
}

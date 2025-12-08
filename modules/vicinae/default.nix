{ config, lib, pkgs, vicinae, ... }:

{
  imports = [
    vicinae.homeManagerModules.default
  ];

  services.vicinae = {
    enable = true;
    autoStart = true;
  };

  # services.vicinae = {
  #   autoStart = true;
  #   settings = {
  #     font.size = 11;
  #     theme.name = "vicinae-dark";
  #     window = {
  #       csd = true;
  #       opacity = 0.95;
  #       rounding = 10;
  #     };
  #   };
  # };
}


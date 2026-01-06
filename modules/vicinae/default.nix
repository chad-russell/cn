{ config, lib, pkgs, ... }:

{
  programs.vicinae = {
    enable = true;
    systemd.autoStart = true;
  };
}


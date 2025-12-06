{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.weztermModule;
in {
  options.programs.weztermModule = {
    enable = mkEnableOption "WezTerm terminal emulator with custom configuration";
  };

  config = mkIf cfg.enable {
    programs.wezterm = {
      enable = true;
      enableZshIntegration = true;
      extraConfig = builtins.readFile ./wezterm.lua;
    };
  };
}


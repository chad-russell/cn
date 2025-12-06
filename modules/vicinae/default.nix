{ config, lib, pkgs, vicinae, ... }:

with lib;

let
  cfg = config.services.vicinaeModule;
in {
  imports = [
    vicinae.homeManagerModules.default
  ];

  options.services.vicinaeModule = {
    enable = mkEnableOption "Vicinae workspace switcher";

    autoStart = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to start Vicinae automatically";
    };

    settings = mkOption {
      type = types.attrs;
      default = {};
      description = "Vicinae configuration settings";
    };
  };

  config = mkIf cfg.enable {
    services.vicinae = {
      enable = true;
      autoStart = cfg.autoStart;
      settings = cfg.settings;
    };
  };
}


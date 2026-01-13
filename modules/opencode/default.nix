{ config, lib, pkgs, ... }:

let
  opencodeModule = config.modulesPath + "/opencode";
in
{
  config = {
    home.file.".config/opencode" = {
      recursive = true;
      source = "${opencodeModule}/config";
    };

    home.file.".local/bin/setup-opencode-plugin" = {
      executable = true;
      text = builtins.readFile "${opencodeModule}/setup-opencode-plugin.sh";
    };

    home.activation.setupOpencodePlugin = ''
      ${config.home.homeDirectory}/.local/bin/setup-opencode-plugin
    '';
  };
}

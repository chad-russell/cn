{ config, lib, pkgs, opencode, ... }:

let
  # Get the directory of this file
  moduleDir = builtins.dirOf ./.;
  opencodeWrapped = pkgs.writeShellScriptBin "opencode" ''
    exec ${opencode.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/opencode --hostname 0.0.0.0 "$@"
  '';
in
{
  config = {
    home.file.".config/opencode" = {
      recursive = true;
      source = "${moduleDir}/config";
    };

    home.file.".local/bin/setup-opencode-plugin" = {
      executable = true;
      text = builtins.readFile "${moduleDir}/setup-opencode-plugin.sh";
    };

    home.activation.setupOpencodePlugin = ''
      ${config.home.homeDirectory}/.local/bin/setup-opencode-plugin
    '';

    # Override the opencode package with a wrapped version that listens on 0.0.0.0
    home.packages = [ opencodeWrapped ];
  };
}

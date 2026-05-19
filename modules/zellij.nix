{
  config,
  pkgs,
  lib,
  ...
}:
{
  programs.zellij = {
    enable = true;
  };

  # Config file is sourced from the host that imports this module
  # (each host can point to its own config.kdl)
}

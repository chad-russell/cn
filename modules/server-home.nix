# ── Server Home Manager Configuration ─────────────────────────────
#
# Minimal home-manager config for server hosts (bee, bees).
# Imports the shared neovim config from the thinkpad setup.

{ config, pkgs, lib, ... }:

let
  username = "crussell";
in
{
  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "25.11";

  # Only manage neovim — shell is handled by modules/server-shell.nix
  imports = [
    ../thinkpad/nvim
  ];

  programs.home-manager.enable = true;

  # Default editor
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
}

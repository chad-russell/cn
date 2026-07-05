# ── Server Home Manager Configuration ─────────────────────────────
#
# Minimal home-manager config for server hosts (bee, bees).

{ ... }:

{
  home.username = "crussell";
  home.homeDirectory = "/home/crussell";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;

  # Default editor (vim is installed via modules/base-server.nix)
  home.sessionVariables = {
    EDITOR = "vim";
    VISUAL = "vim";
  };
}

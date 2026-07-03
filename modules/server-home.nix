# ── Server Home Manager Configuration ─────────────────────────────
#
# Minimal home-manager config for server hosts (bee, bees).
# Imports the shared neovim config from the thinkpad setup.

{ config, pkgs, lib, unstable, ... }:

let
  username = "crussell";
in
{
  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "25.11";

  # Only manage neovim — shell is handled by modules/server-shell.nix
  imports = [
    ../hosts/thinkpad/nvim
  ];

  # The shared nvim config uses Neovim 0.12+ features (pumborder, vim.lsp.config, etc.)
  # but the server nixpkgs (nixos-25.11) ships 0.11.x. Pin to unstable neovim.
  programs.nixvim.package = lib.mkForce unstable.neovim-unwrapped;

  programs.home-manager.enable = true;

  # Default editor
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
}

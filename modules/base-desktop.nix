{ config, pkgs, ... }:

{
  # Enable passwordless sudo for wheel group members
  security.sudo.wheelNeedsPassword = false;

  # Set your time zone
  time.timeZone = "America/New_York";

  # Enable zsh system-wide
  programs.zsh.enable = true;

  # Basic packages
  environment.systemPackages = with pkgs; [
    git
    vim
    htop
    gh
    alsa-utils
    code-cursor-fhs
    antigravity-fhs
    _1password-gui
  ];

  # Enable experimental Nix features
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
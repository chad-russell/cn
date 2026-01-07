{ config, pkgs, ... }:

{
  # Enable passwordless sudo for wheel group members
  security.sudo.wheelNeedsPassword = false;

  # Set your time zone
  time.timeZone = "America/New_York";

  # Enable zsh system-wide
  programs.zsh.enable = true;

  # SSH
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "prohibit-password";

  # Nix settings
  nix.settings = {
    trusted-users = [
      "root"
      "crussell"
    ];
    substituters = [
      "https://cache.nixos.org"
      "https://numtide.cachix.org"
      "https://niri.cachix.org"
    ];
    trusted-public-keys = [
      "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
      "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
    ];
  };

  # Enable Steam
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # Opens ports for Steam Remote Play
    dedicatedServer.openFirewall = true; # Opens ports for Source Dedicated Server
  };

  # Automatic garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Also limit the number of generations system-wide
  nix.settings.auto-optimise-store = true; # Optimize store by hardlinking identical files

  # Basic packages
  environment.systemPackages = with pkgs; [
    home-manager
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
{ config, pkgs, ... }:

{
  # Enable Docker (needed for distrobox)
  virtualisation.docker.enable = true;
  virtualisation.docker.enableOnBoot = true;
  
  # Enable Podman as alternative
  virtualisation.podman.enable = true;
  virtualisation.podman.defaultNetwork.settings.dns_enabled = true;
}

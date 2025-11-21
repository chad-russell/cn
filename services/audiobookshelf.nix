{ config, ... }:

{
  # Audiobookshelf - Self-hosted audiobook and podcast server
  # Using Docker via virtualisation.oci-containers for reliable DNS
  
  # Create Docker network for Audiobookshelf
  systemd.services.init-audiobookshelf-network = {
    description = "Create Docker network for Audiobookshelf";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${config.virtualisation.docker.package}/bin/docker network inspect audiobookshelf >/dev/null 2>&1 || \
      ${config.virtualisation.docker.package}/bin/docker network create audiobookshelf
    '';
  };

  virtualisation.oci-containers.containers = {
    audiobookshelf = {
      image = "ghcr.io/advplyr/audiobookshelf:latest";
      autoStart = true;
      ports = [ "13378:80" ];
      extraOptions = [ "--network=audiobookshelf" ];
      volumes = [
        "audiobookshelf-config:/config"
        "audiobookshelf-metadata:/metadata"
        "audiobookshelf-audiobooks:/audiobooks"
        "audiobookshelf-podcasts:/podcasts"
      ];
      environment = {
        TZ = "America/New_York";
      };
    };
  };
  
  # Open firewall port for Audiobookshelf
  networking.firewall.allowedTCPPorts = [ 13378 ];
}


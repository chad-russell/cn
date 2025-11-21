{ config, ... }:

{
  # SearXNG - Privacy-respecting metasearch engine
  # Using Docker via virtualisation.oci-containers for reliable DNS
  
  # Create Docker network for SearXNG
  systemd.services.init-searxng-network = {
    description = "Create Docker network for SearXNG";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${config.virtualisation.docker.package}/bin/docker network inspect searxng >/dev/null 2>&1 || \
      ${config.virtualisation.docker.package}/bin/docker network create searxng
    '';
  };

  virtualisation.oci-containers.containers = {
    searxng-valkey = {
      image = "valkey/valkey:8-alpine";
      autoStart = true;
      extraOptions = [ "--network=searxng" ];
      volumes = [ "searxng-valkey-data:/data" ];
      cmd = [
        "valkey-server"
        "--save"
        "30"
        "1"
        "--loglevel"
        "warning"
      ];
    };

    searxng = {
      image = "searxng/searxng:latest";
      autoStart = true;
      ports = [ "8080:8080" ];
      extraOptions = [ "--network=searxng" ];
      volumes = [
        "searxng-config:/etc/searxng"
        "searxng-cache:/var/cache/searxng"
      ];
      environment = {
        # Base URL for SearXNG
        SEARXNG_BASE_URL = "https://searxng.internal.crussell.io/";
      };
      dependsOn = [ "searxng-valkey" ];
    };
  };
}


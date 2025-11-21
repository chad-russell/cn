{ config, ... }:

{
  # Papra - Document Management System
  # Using Docker via virtualisation.oci-containers for reliable DNS
  
  # Create Docker network for Papra
  systemd.services.init-papra-network = {
    description = "Create Docker network for Papra";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${config.virtualisation.docker.package}/bin/docker network inspect papra >/dev/null 2>&1 || \
      ${config.virtualisation.docker.package}/bin/docker network create papra
    '';
  };

  virtualisation.oci-containers.containers = {
    papra = {
      image = "ghcr.io/papra-hq/papra:latest";
      autoStart = true;
      ports = [ "1221:1221" ];
      extraOptions = [ "--network=papra" ];
      volumes = [ "papra-data:/app/app-data" ];
      environment = {
        # CHANGE THIS: Set to your actual Papra URL
        APP_BASE_URL = "https://papra.internal.crussell.io";
        TZ = "America/New_York";
        # Optional configuration:
        # PAPRA_LOG_LEVEL = "info";
        # PAPRA_MAX_UPLOAD_SIZE = "50MB";
      };
    };
  };
}

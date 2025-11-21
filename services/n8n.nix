{ config, ... }:

{
  # n8n - Workflow Automation Platform
  # Using Docker via virtualisation.oci-containers for reliable DNS
  
  # Create Docker network for n8n
  systemd.services.init-n8n-network = {
    description = "Create Docker network for n8n";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${config.virtualisation.docker.package}/bin/docker network inspect n8n >/dev/null 2>&1 || \
      ${config.virtualisation.docker.package}/bin/docker network create n8n
    '';
  };

  virtualisation.oci-containers.containers = {
    n8n = {
      image = "docker.n8n.io/n8nio/n8n:latest";
      autoStart = true;
      ports = [ "5678:5678" ];
      extraOptions = [ "--network=n8n" ];
      volumes = [
        "n8n-data:/home/node/.n8n"
        "n8n-files:/files"
      ];
      environment = {
        # Basic Configuration
        N8N_HOST = "n8n.crussell.io";
        N8N_PORT = "5678";
        N8N_PROTOCOL = "https";
        WEBHOOK_URL = "https://n8n.crussell.io/";
        
        # Timezone Configuration
        GENERIC_TIMEZONE = "America/New_York";
        TZ = "America/New_York";
        
        # Production Settings
        NODE_ENV = "production";
        N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS = "true";
        
        # Enable runners for better performance
        N8N_RUNNERS_ENABLED = "true";
      };
    };
  };
}


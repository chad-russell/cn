{ config, ... }:

{
  # Beszel Hub - Lightweight server monitoring platform web interface
  # Using Docker via virtualisation.oci-containers
  
  virtualisation.oci-containers.containers = {
    beszel = {
      image = "henrygd/beszel:latest";
      autoStart = true;
      ports = [ "8090:8090" ];
      volumes = [
        "beszel-data:/beszel_data"
      ];
      environment = {
        # Timezone setting
        TZ = "America/New_York";
      };
    };
  };
  
  # Open firewall port for beszel hub web interface
  networking.firewall.allowedTCPPorts = [ 8090 ];
}


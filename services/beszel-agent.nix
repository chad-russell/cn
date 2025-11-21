{ config, ... }:

{
  # Beszel Agent - Reports system metrics to beszel hub
  # Using Docker via virtualisation.oci-containers
  
  virtualisation.oci-containers.containers = {
    beszel-agent = {
      image = "henrygd/beszel-agent:latest";
      autoStart = true;
      ports = [ "45876:45876" ];
      volumes = [
        "/var/run/docker.sock:/var/run/docker.sock:ro"
        "/:/host:ro"  # For host filesystem metrics
      ];
      environment = {
        # Timezone setting
        TZ = "America/New_York";
        
        # Port the agent listens on (default 45876)
        PORT = "45876";
        
        # Public key for authentication (from beszel hub)
        # Set in each machine's configuration.nix:
        # virtualisation.oci-containers.containers.beszel-agent.environment.KEY = "ssh-ed25519 ...";
      };
      extraOptions = [
        "--privileged"  # Needed for full system metrics
      ];
    };
  };
  
  # Open firewall port for beszel agent
  networking.firewall.allowedTCPPorts = [ 45876 ];
}


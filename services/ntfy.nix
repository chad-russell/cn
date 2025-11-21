{ config, ... }:

{
  # ntfy - Simple HTTP-based pub-sub notification service
  # Using Docker via virtualisation.oci-containers for reliable DNS
  
  # Create Docker network for ntfy
  systemd.services.init-ntfy-network = {
    description = "Create Docker network for ntfy";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${config.virtualisation.docker.package}/bin/docker network inspect ntfy >/dev/null 2>&1 || \
      ${config.virtualisation.docker.package}/bin/docker network create ntfy
    '';
  };

  virtualisation.oci-containers.containers = {
    ntfy = {
      image = "docker.io/binwiederhier/ntfy:v2.11.0";
      autoStart = true;
      ports = [ "8090:80" ];
      extraOptions = [ "--network=ntfy" ];
      volumes = [
        "ntfy-cache:/var/cache/ntfy"
        "ntfy-config:/etc/ntfy"
      ];
      environment = {
        TZ = "America/New_York";
      };
      # Command to run ntfy server
      cmd = [ "serve" ];
    };
  };
}

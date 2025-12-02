{ config, ... }:

{
  # Memos - A privacy-first, lightweight note-taking service
  # Using Docker via virtualisation.oci-containers for reliable DNS
  
  # Create Docker network for Memos
  systemd.services.init-memos-network = {
    description = "Create Docker network for Memos";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${config.virtualisation.docker.package}/bin/docker network inspect memos >/dev/null 2>&1 || \
      ${config.virtualisation.docker.package}/bin/docker network create memos
    '';
  };

  virtualisation.oci-containers.containers = {
    memos = {
      image = "docker.io/neosmemo/memos:stable";
      autoStart = true;
      ports = [ "5230:5230" ];
      extraOptions = [ "--network=memos" ];
      volumes = [ "memos-data:/var/opt/memos" ];
      # Optional: Add environment variables for configuration
      # environment = {
      #   MEMOS_DRIVER = "postgres";
      #   MEMOS_DSN = "postgresql://user:password@host:port/dbname";
      #   MEMOS_MODE = "prod";
      #   MEMOS_ADDR = "0.0.0.0";
      #   MEMOS_PORT = "5230";
      # };
    };
  };
}

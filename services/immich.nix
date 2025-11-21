{ config, ... }:

{
  # Immich - Self-hosted photo and video management solution
  # Using Docker via virtualisation.oci-containers for reliable DNS
  
  # Create Docker network for Immich
  systemd.services.init-immich-network = {
    description = "Create Docker network for Immich";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${config.virtualisation.docker.package}/bin/docker network inspect immich >/dev/null 2>&1 || \
      ${config.virtualisation.docker.package}/bin/docker network create immich
    '';
  };

  virtualisation.oci-containers.containers = {
    # PostgreSQL database for Immich
    immich-postgres = {
      image = "docker.io/tensorchord/pgvecto-rs:pg14-v0.2.0";
      autoStart = true;
      extraOptions = [ "--network=immich" ];
      volumes = [ "immich-pgdata:/var/lib/postgresql/data" ];
      environment = {
        POSTGRES_DB = "immich";
        POSTGRES_USER = "postgres";
        POSTGRES_PASSWORD = "postgres";  # CHANGE THIS: Use a secure password
        POSTGRES_INITDB_ARGS = "--data-checksums";
      };
      cmd = [
        "postgres"
        "-c"
        "shared_preload_libraries=vectors.so"
        "-c"
        "search_path=\"$$user\", public, vectors"
        "-c"
        "logging_collector=on"
        "-c"
        "max_wal_size=2GB"
        "-c"
        "shared_buffers=512MB"
        "-c"
        "wal_compression=on"
      ];
    };

    # Redis for caching
    immich-redis = {
      image = "docker.io/redis:6.2-alpine";
      autoStart = true;
      extraOptions = [ "--network=immich" ];
      volumes = [ "immich-redis-data:/data" ];
    };

    # Immich Server
    immich-server = {
      image = "ghcr.io/immich-app/immich-server:release";
      autoStart = true;
      ports = [ "2283:2283" ];
      extraOptions = [ "--network=immich" ];
      volumes = [
        # Use NFS mount from TrueNAS for photo storage
        "/mnt/immich:/usr/src/app/upload"
        "/etc/localtime:/etc/localtime:ro"
      ];
      environment = {
        # Database Configuration
        DB_HOSTNAME = "immich-postgres";
        DB_USERNAME = "postgres";
        DB_PASSWORD = "postgres";  # CHANGE THIS: Match postgres password
        DB_DATABASE_NAME = "immich";
        
        # Redis Configuration
        REDIS_HOSTNAME = "immich-redis";
        
        # Timezone
        TZ = "America/New_York";
        
        # Server URL
        PUBLIC_IMMICH_SERVER_URL = "https://immich.crussell.io";
      };
      dependsOn = [ "immich-postgres" "immich-redis" ];
    };

    # Immich Machine Learning
    immich-machine-learning = {
      image = "ghcr.io/immich-app/immich-machine-learning:release";
      autoStart = true;
      extraOptions = [ "--network=immich" ];
      volumes = [
        "immich-model-cache:/cache"
      ];
      environment = {
        TZ = "America/New_York";
      };
    };
  };
  
  # Open firewall port for Immich web interface
  networking.firewall.allowedTCPPorts = [ 2283 ];
}


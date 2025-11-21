{ config, ... }:

{
  # PinePods - Podcast Management System
  # Using Docker via virtualisation.oci-containers for reliable DNS
  
  # Create Docker network for PinePods
  systemd.services.init-pinepods-network = {
    description = "Create Docker network for PinePods";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${config.virtualisation.docker.package}/bin/docker network inspect pinepods >/dev/null 2>&1 || \
      ${config.virtualisation.docker.package}/bin/docker network create pinepods
    '';
  };

  virtualisation.oci-containers.containers = {
    pinepods-db = {
      image = "postgres:17";
      autoStart = true;
      extraOptions = [ "--network=pinepods" ];
      volumes = [ "pinepods-pgdata:/var/lib/postgresql/data" ];
      environment = {
        POSTGRES_DB = "pinepods_database";
        POSTGRES_USER = "postgres";
        POSTGRES_PASSWORD = "myS3curepass";
        PGDATA = "/var/lib/postgresql/data/pgdata";
      };
    };

    pinepods-valkey = {
      image = "valkey/valkey:8-alpine";
      autoStart = true;
      extraOptions = [ "--network=pinepods" ];
    };

    pinepods = {
      image = "madeofpendletonwool/pinepods:latest";
      autoStart = true;
      ports = [ "8040:8040" ];
      extraOptions = [ "--network=pinepods" ];
      volumes = [
        "pinepods-downloads:/opt/pinepods/downloads"
        "pinepods-backups:/opt/pinepods/backups"
      ];
      environment = {
        # Basic Server Info
        SEARCH_API_URL = "https://search.pinepods.online/api/search";
        PEOPLE_API_URL = "https://people.pinepods.online";
        HOSTNAME = "https://pinepods.internal.crussell.io";
        
        # Database Configuration
        DB_TYPE = "postgresql";
        DB_HOST = "pinepods-db";
        DB_PORT = "5432";
        DB_USER = "postgres";
        DB_PASSWORD = "myS3curepass";
        DB_NAME = "pinepods_database";
        
        # Valkey Settings
        VALKEY_HOST = "pinepods-valkey";
        VALKEY_PORT = "6379";
        
        # Debug and User Settings
        DEBUG_MODE = "false";
        PUID = "911";
        PGID = "911";
        TZ = "America/New_York";
      };
      dependsOn = [ "pinepods-db" "pinepods-valkey" ];
    };
  };
}


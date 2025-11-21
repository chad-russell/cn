{ config, ... }:

{
  # Karakeep - Bookmark Manager with AI-powered features
  # Using Docker via virtualisation.oci-containers for reliable DNS
  
  # Create Docker network for Karakeep
  systemd.services.init-karakeep-network = {
    description = "Create Docker network for Karakeep";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${config.virtualisation.docker.package}/bin/docker network inspect karakeep >/dev/null 2>&1 || \
      ${config.virtualisation.docker.package}/bin/docker network create karakeep
    '';
  };

  virtualisation.oci-containers.containers = {
    # Chrome container for web scraping
    karakeep-chrome = {
      image = "gcr.io/zenika-hub/alpine-chrome:124";
      autoStart = true;
      extraOptions = [ "--network=karakeep" ];
      cmd = [
        "--no-sandbox"
        "--disable-gpu"
        "--disable-dev-shm-usage"
        "--remote-debugging-address=0.0.0.0"
        "--remote-debugging-port=9222"
        "--hide-scrollbars"
      ];
    };

    # Meilisearch search engine
    karakeep-meilisearch = {
      image = "docker.io/getmeili/meilisearch:v1.10";
      autoStart = true;
      extraOptions = [ "--network=karakeep" ];
      volumes = [ "karakeep-data:/meili_data" ];
      environment = {
        # CHANGE THIS: Generate a secure master key with: openssl rand -base64 36
        MEILI_MASTER_KEY = "IrLHvlILqJDWOufv/wweLQondy1+rq3JufEOXoJg/2sMjkGS";
      };
    };

    # Main Karakeep application
    karakeep = {
      image = "ghcr.io/karakeep-app/karakeep:release";
      autoStart = true;
      ports = [ "3322:3000" ];
      extraOptions = [ "--network=karakeep" ];
      volumes = [ "karakeep-app-data:/data" ];
      environment = {
        # CHANGE THIS: Generate a secure secret with: openssl rand -base64 36
        NEXTAUTH_SECRET = "FLGHUFil//n1atELBxGFD7FNF9D8Jpom9cFLHrB1JFFWmuyp";
        # CHANGE THIS: Set to your actual server URL
        NEXTAUTH_URL = "https://karakeep.internal.crussell.io";
        DATA_DIR = "/data";
        # Meilisearch configuration
        MEILI_ADDR = "http://karakeep-meilisearch:7700";
        MEILI_MASTER_KEY = "IrLHvlILqJDWOufv/wweLQondy1+rq3JufEOXoJg/2sMjkGS";
        # Chrome configuration
        BROWSER_WEB_URL = "http://karakeep-chrome:9222";
      };
      dependsOn = [ "karakeep-meilisearch" "karakeep-chrome" ];
    };

    # HomeDash - Compact bookmark dashboard
    karakeep-homedash = {
      image = "ghcr.io/codejawn/karakeep-homedash:latest";
      autoStart = true;
      ports = [ "8595:8595" ];
      extraOptions = [ "--network=karakeep" ];
      volumes = [
        "karakeep-app-data:/mnt/karakeep-data:ro"
        "karakeep-homedash-config:/app/config"
      ];
      cmd = [
        "/bin/sh"
        "-c"
        "ln -sf /mnt/karakeep-data/db.db /app/db.db && python3 server.py"
      ];
      environment = {
        # CHANGE THIS: Set to your actual KaraKeep URL
        KARAKEEP_URL = "https://karakeep.internal.crussell.io";
      };
      dependsOn = [ "karakeep" ];
    };
  };
}

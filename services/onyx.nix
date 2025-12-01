{ config, ... }:

{
  imports = [
    ../secrets/secrets.nix
  ];

  # Onyx - AI-powered search and chat platform
  # Using Docker via virtualisation.oci-containers for reliable DNS
  
  # Create Docker network for Onyx
  systemd.services.init-onyx-network = {
    description = "Create Docker network for Onyx";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${config.virtualisation.docker.package}/bin/docker network inspect onyx >/dev/null 2>&1 || \
      ${config.virtualisation.docker.package}/bin/docker network create onyx
    '';
  };

  virtualisation.oci-containers.containers = {
    # PostgreSQL database for Onyx
    onyx-relational-db = {
      image = "postgres:15.2-alpine";
      autoStart = true;
      extraOptions = [ 
        "--network=onyx"
        "--shm-size=1g"
      ];
      volumes = [ "onyx-db-volume:/var/lib/postgresql/data" ];
      environment = {
        POSTGRES_USER = "postgres";
        POSTGRES_PASSWORD = config.mySecrets.onyx.postgres_password or "password";
      };
      cmd = [ "-c" "max_connections=250" ];
    };

    # Vespa search engine
    onyx-index = {
      image = "vespaengine/vespa:8.609.39";
      autoStart = true;
      extraOptions = [ "--network=onyx" ];
      volumes = [ "onyx-vespa-volume:/opt/vespa/var" ];
      environment = {
        VESPA_SKIP_UPGRADE_CHECK = "true";
      };
    };

    # Redis cache
    onyx-cache = {
      image = "redis:7.4-alpine";
      autoStart = true;
      extraOptions = [ 
        "--network=onyx"
        "--tmpfs=/data"
      ];
      cmd = [ "redis-server" "--save" "" "--appendonly" "no" ];
    };

    # MinIO object storage
    onyx-minio = {
      image = "minio/minio:RELEASE.2025-07-23T15-54-02Z-cpuv1";
      autoStart = true;
      extraOptions = [ "--network=onyx" ];
      volumes = [ "onyx-minio-data:/data" ];
      environment = {
        MINIO_ROOT_USER = "minioadmin";
        MINIO_ROOT_PASSWORD = config.mySecrets.onyx.minio_root_password or "minioadmin";
        MINIO_DEFAULT_BUCKETS = "onyx-file-store-bucket";
      };
      cmd = [ "server" "/data" "--console-address" ":9001" ];
    };

    # Inference model server
    onyx-inference-model-server = {
      image = "onyxdotapp/onyx-model-server:latest";
      autoStart = true;
      extraOptions = [ "--network=onyx" ];
      volumes = [ 
        "onyx-model-cache-huggingface:/app/.cache/huggingface/"
        "onyx-inference-model-server-logs:/var/log/onyx"
      ];
      cmd = [ 
        "/bin/sh" "-c"
        "exec uvicorn model_server.main:app --host 0.0.0.0 --port 9000"
      ];
    };

    # Indexing model server
    onyx-indexing-model-server = {
      image = "onyxdotapp/onyx-model-server:latest";
      autoStart = true;
      extraOptions = [ "--network=onyx" ];
      volumes = [ 
        "onyx-indexing-huggingface-model-cache:/app/.cache/huggingface/"
        "onyx-indexing-model-server-logs:/var/log/onyx"
      ];
      environment = {
        INDEXING_ONLY = "True";
      };
      cmd = [ 
        "/bin/sh" "-c"
        "exec uvicorn model_server.main:app --host 0.0.0.0 --port 9000"
      ];
    };

    # Background worker
    onyx-background = {
      image = "onyxdotapp/onyx-backend:latest";
      autoStart = true;
      extraOptions = [ 
        "--network=onyx"
        "--add-host=host.docker.internal:host-gateway"
      ];
      volumes = [ "onyx-background-logs:/var/log/onyx" ];
      environment = {
        USE_LIGHTWEIGHT_BACKGROUND_WORKER = "true";
        POSTGRES_HOST = "onyx-relational-db";
        VESPA_HOST = "onyx-index";
        REDIS_HOST = "onyx-cache";
        MODEL_SERVER_HOST = "onyx-inference-model-server";
        INDEXING_MODEL_SERVER_HOST = "onyx-indexing-model-server";
        S3_ENDPOINT_URL = "http://onyx-minio:9000";
        S3_AWS_ACCESS_KEY_ID = "minioadmin";
        S3_AWS_SECRET_ACCESS_KEY = config.mySecrets.onyx.minio_root_password or "minioadmin";
      };
      cmd = [ 
        "/bin/sh" "-c"
        "if [ -f /etc/ssl/certs/custom-ca.crt ]; then update-ca-certificates; fi && /app/scripts/supervisord_entrypoint.sh"
      ];
      dependsOn = [ 
        "onyx-relational-db" 
        "onyx-index" 
        "onyx-cache" 
        "onyx-inference-model-server"
        "onyx-indexing-model-server"
      ];
    };

    # API Server
    onyx-api-server = {
      image = "onyxdotapp/onyx-backend:latest";
      autoStart = true;
      extraOptions = [ 
        "--network=onyx"
        "--add-host=host.docker.internal:host-gateway"
      ];
      volumes = [ "onyx-api-server-logs:/var/log/onyx" ];
      environment = {
        AUTH_TYPE = "basic";
        POSTGRES_HOST = "onyx-relational-db";
        VESPA_HOST = "onyx-index";
        REDIS_HOST = "onyx-cache";
        MODEL_SERVER_HOST = "onyx-inference-model-server";
        S3_ENDPOINT_URL = "http://onyx-minio:9000";
        S3_AWS_ACCESS_KEY_ID = "minioadmin";
        S3_AWS_SECRET_ACCESS_KEY = config.mySecrets.onyx.minio_root_password or "minioadmin";
      };
      cmd = [ 
        "/bin/sh" "-c"
        "alembic upgrade head && echo \"Starting Onyx Api Server\" && uvicorn onyx.main:app --host 0.0.0.0 --port 8080"
      ];
      dependsOn = [ 
        "onyx-relational-db" 
        "onyx-index" 
        "onyx-cache" 
        "onyx-inference-model-server"
        "onyx-minio"
      ];
    };

    # Web Server
    onyx-web-server = {
      image = "onyxdotapp/onyx-web-server:latest";
      autoStart = true;
      ports = [ "3033:3000" ];  # Expose on port 3033, web server runs on 3000
      extraOptions = [ "--network=onyx" ];
      environment = {
        INTERNAL_URL = "http://onyx-api-server:8080";
      };
      dependsOn = [ "onyx-api-server" ];
    };

    # Code interpreter (optional, disabled by default)
    onyx-code-interpreter = {
      image = "onyxdotapp/code-interpreter:latest";
      autoStart = true;
      extraOptions = [ 
        "--network=onyx"
        "--user=root"
      ];
      volumes = [ "/var/run/docker.sock:/var/run/docker.sock" ];
      environment = {
        CODE_INTERPRETER_BETA_ENABLED = "false";
      };
      cmd = [ 
        "/bin/bash" "-c"
        "if [ \"$CODE_INTERPRETER_BETA_ENABLED\" = \"True\" ] || [ \"$CODE_INTERPRETER_BETA_ENABLED\" = \"true\" ]; then exec bash ./entrypoint.sh code-interpreter-api; else echo 'Skipping code interpreter'; exec tail -f /dev/null; fi"
      ];
    };
  };
  
  # Open firewall port for Onyx web interface
  networking.firewall.allowedTCPPorts = [ 3033 ];
}

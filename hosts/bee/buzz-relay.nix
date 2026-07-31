# ── Buzz self-hosted relay (podman quadlet pod on bee) ────────────────
#
# Runs the Buzz relay + Postgres + Redis + MinIO as a podman pod, mirroring
# upstream deploy/compose/compose.yml. Terminated at the gateway by Caddy and
# served at wss://buzz.crussell.io. All containers share the pod's network
# namespace, so inter-service addressing is localhost (no DNS names needed).
#
# Secrets live in one agenix env file (secrets/buzz-relay-env.age); quadlet
# EnvironmentFile does not expand $VAR, so connection strings carry inlined
# values there. MinIO is bound to host localhost only (for the bucket-init
# oneshot); only the relay port 3000 is reachable on the LAN/Nebula.

{ config, pkgs, ... }:

{
  age.secrets.buzz-relay-env.file = ../../secrets/buzz-relay-env.age;

  # Quadlet definitions → /etc/containers/systemd/ (rootful podman).
  environment.etc = {
    "containers/systemd/buzz-relay.pod".source = ./buzz-relay.pod;
    "containers/systemd/buzz-relay.container".source = ./buzz-relay.container;
    "containers/systemd/buzz-postgres.container".source = ./buzz-postgres.container;
    "containers/systemd/buzz-redis.container".source = ./buzz-redis.container;
    "containers/systemd/buzz-minio.container".source = ./buzz-minio.container;
  };

  # Idempotently create the buzz-media bucket once MinIO is accepting
  # connections. Reaches MinIO at 127.0.0.1:9000 (pod publishes it to host
  # localhost only). Retries for up to ~30s so it tolerates MinIO startup lag.
  systemd.services.buzz-minio-init = {
    description = "Create buzz-media MinIO bucket";
    after = [ "buzz-minio.service" ];
    requires = [ "buzz-minio.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    environmentFile = [ config.age.secrets.buzz-relay-env.path ];
    path = [ pkgs.minio-client ];
    script = ''
      set -e
      for i in $(seq 1 30); do
        if mc alias set local http://127.0.0.1:9000 "$BUZZ_S3_ACCESS_KEY" "$BUZZ_S3_SECRET_KEY" >/dev/null 2>&1; then
          break
        fi
        sleep 1
      done
      mc alias set local http://127.0.0.1:9000 "$BUZZ_S3_ACCESS_KEY" "$BUZZ_S3_SECRET_KEY"
      mc mb --ignore-existing local/buzz-media
      mc anonymous set none local/buzz-media
      echo "bucket buzz-media ready"
    '';
  };
}

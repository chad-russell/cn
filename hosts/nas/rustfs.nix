# ── nas: shared RustFS S3 object store ──────────────────────────────
#
# Quadlet + pool layout + bucket bootstrap + health check. Trigger and
# design rationale: docs/rustfs-migration/PLAN.md "Deferred design"
# section — central logging fired the trigger (2026-09-25).

{ config, lib, pkgs, ... }:

{
  environment.etc."containers/systemd/rustfs.container" = {
    source = ./rustfs.container;
    mode = "0644";
  };

  # nas had no podman workload until now — the quadlet generator needs it.
  virtualisation.podman.enable = true;

  # Cross-host published ports need forwarding since netavark stopped
  # flipping it (bees lesson, 2026-09-05 fleet bump — jellyfin 502).
  boot.kernel.sysctl."net.ipv4.conf.all.forwarding" = true;

  # Multi-directory pool per PLAN.md (single-path SNSD unsupported). The
  # rustfs image runs as 10001:10001, so the bind-mounted pool dirs carry
  # that numeric uid/gid (tmpfiles accepts numeric ids without a user).
  systemd.tmpfiles.rules = [
    "d /pool/rustfs     0755 10001 10001 -"
    "d /pool/rustfs/d0  0755 10001 10001 -"
    "d /pool/rustfs/d1  0755 10001 10001 -"
    "d /pool/rustfs/d2  0755 10001 10001 -"
    "d /pool/rustfs/d3  0755 10001 10001 -"
  ];

  # S3 API on the Nebula IP only (published 10.10.0.3:9000). NFS opens
  # 2049 the same way; the only listener on 9000 is the overlay-bound
  # published port.
  networking.firewall.allowedTCPPorts = [ 9000 ];

  # RUSTFS_ACCESS_KEY / RUSTFS_SECRET_KEY — values duplicated as ZO_S3_*
  # in secrets/openobserve-env.age (what bees' OpenObserve quadlet reads):
  # rotate both files together.
  age.secrets.rustfs-env.file = ../../secrets/rustfs-env.age;

  # Idempotent bucket bootstrap — OpenObserve does not create its bucket.
  # Retries until rustfs answers, then no-ops on every boot/redeploy.
  systemd.services.rustfs-bucket-init = {
    description = "Create openobserve bucket in RustFS";
    after = [ "rustfs.service" ];
    wants = [ "rustfs.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.awscli2 ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = config.age.secrets.rustfs-env.path;
      RemainAfterExit = true;
    };
    script = ''
      export AWS_ACCESS_KEY_ID="$RUSTFS_ACCESS_KEY"
      export AWS_SECRET_ACCESS_KEY="$RUSTFS_SECRET_KEY"
      export AWS_REGION=us-east-1
      for i in $(seq 1 30); do
        if aws --endpoint-url http://10.10.0.3:9000 s3api head-bucket \
            --bucket openobserve >/dev/null 2>&1; then
          echo "bucket openobserve present"
          exit 0
        fi
        if aws --endpoint-url http://10.10.0.3:9000 s3api create-bucket \
            --bucket openobserve >/dev/null 2>&1; then
          echo "bucket openobserve created"
          exit 0
        fi
        sleep 10
      done
      echo "rustfs never became ready" >&2
      exit 1
    '';
  };

  homelab.freshnessChecks.nas-rustfs = {
    description = "nas rustfs health";
    extraPath = [ pkgs.curl ];
    checkCommand = ''
      code=$(curl -s -o /dev/null -w '%{http_code}' http://10.10.0.3:9000/health/ready)
      echo "rustfs /health/ready -> $code"
      [ "$code" = "200" ]
    '';
  };
}

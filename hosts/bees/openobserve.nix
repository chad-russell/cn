# ── bees: OpenObserve central log search ────────────────────────────
#
# Quadlet source + secret + health freshness check. Data plane: see
# openobserve.container header. Every host's Vector shipper feeds it
# (modules/vector-log-shipper.nix); parquet lands in RustFS on nas.

{ config, lib, pkgs, ... }:

{
  environment.etc."containers/systemd/openobserve.container" = {
    source = ./openobserve.container;
    mode = "0644";
  };

  # ZO_ROOT_USER_EMAIL / ZO_ROOT_USER_PASSWORD (UI login AND OTLP basic
  # auth for every Vector shipper) + ZO_S3_ACCESS_KEY / ZO_S3_SECRET_KEY.
  # The S3 values DUPLICATE secrets/rustfs-env.age — rotate both together.
  # Decrypted as root: the rootful quadlet reads it, and on the other
  # hosts systemd reads it for the vector unit before dropping privileges.
  age.secrets.openobserve-env.file = ../../secrets/openobserve-env.age;

  # Crash-loop alerting lives in the .container [Unit] (OnFailure →
  # ntfy-failure@) — a systemd.services override here would write a stub
  # unit shadowing the podman-system-generator output (caddy trap).

  homelab.freshnessChecks.bees-logs = {
    description = "bees openobserve health";
    extraPath = [ pkgs.curl ];
    environmentFile = config.age.secrets.openobserve-env.path;
    checkCommand = ''
      # v1.0.4's /health answers 401 unauthenticated — probe the real
      # API with the root creds instead: proves process + auth + API.
      creds=$(grep -E '^ZO_ROOT_USER_(EMAIL|PASSWORD)=' "$CREDENTIALS_DIRECTORY/openobserve-env" 2>/dev/null || grep -E '^ZO_ROOT_USER_(EMAIL|PASSWORD)=' /run/agenix/openobserve-env)
      u=$(echo "$creds" | grep EMAIL | cut -d= -f2-)
      p=$(echo "$creds" | grep PASSWORD | cut -d= -f2-)
      code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 -u "$u:$p" http://10.10.0.6:5080/api/default/streams)
      echo "openobserve /api/default/streams -> $code"
      [ "$code" = "200" ]
    '';
  };
}

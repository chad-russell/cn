# ── Vector log shipper (journald → OpenObserve) ─────────────────────
#
# Shared module for every NixOS host: ships the full systemd journal as
# OTLP logs to OpenObserve on bees (https://logs.internal.crussell.io).
# Podman quadlet containers log to journald on this fleet, so one source
# covers systemd units AND container output. Mirrors the beszel-agent
# pattern: import it and it's on.
#
# Fields after the remap: message, host, unit (systemd unit or syslog
# identifier, e.g. "kernel"), container (podman CONTAINER_NAME when
# present), level (ERROR/WARNING/INFO/DEBUG from journald PRIORITY),
# timestamp. Raw journald metadata is dropped to keep parquet lean.
#
# Auth: the OpenObserve root user (secrets/openobserve-env.age, shared
# with bees' quadlet). Vector buffers to disk, so logs survive OpenObserve
# or Nebula downtime (bounded at 256 MiB, then backpressure).
#
# VALIDATION GOTCHA (2026-09-25): vector 0.55.0's `validate` subcommand
# is LAXER than run-mode compilation — three broken remaps passed both
# the nixpkgs build-time derivation AND `vector validate`, then failed
# at unit start (exit 78, which aborts switch-to-configuration with
# exit 4 mid-activation). The real gate, in order:
#   1. nix eval --raw ...config.services.vector.package  (THIS flake's
#      pin — never `nix shell nixpkgs#vector`, the registry carries a
#      newer, laxer dialect)
#   2. render ...config.services.vector.settings --json → TOML
#   3. run THAT binary with `--config` for a few seconds (with dummy
#      ZO_* env): config-compile errors appear before runtime resource
#      errors (data_dir/buffer perms failures in a sandbox are FINE —
#      they prove compilation passed).
#
# Usage in a host config:
#
#   imports = [ ../../modules/vector-log-shipper.nix ];
#   # enable defaults to true; per-host tweaks:
#   services.homelab-log-shipper.excludeUnits = [ "something-noisy.service" ];

{ config, lib, pkgs, ... }:

let
  cfg = config.services.homelab-log-shipper;

  remap = ''
    # 0.55 journald schema (empirically confirmed live 2026-09-25): the
    # source HOISTS MESSAGE→.message and _HOSTNAME→.host into Vector's
    # standard schema — those caps fields do NOT exist on the event.
    # Other journal fields keep their CAPS names (.PRIORITY,
    # ._SYSTEMD_UNIT, .CONTAINER_NAME, ...). Reading .MESSAGE/._HOSTNAME
    # and assigning to .message/.host CLOBBERS good values with "".
    #
    # Strategy: capture what we keep, then REPLACE the event wholesale —
    # no del() list to maintain against journal field drift.
    m = to_string(.message) ?? ""
    h = to_string(.host) ?? ""

    u = to_string(._SYSTEMD_UNIT) ?? to_string(.SYSLOG_IDENTIFIER) ?? "unknown"
    u = replace(u, r'\.service$', "")

    cn = to_string(.CONTAINER_NAME) ?? ""

    pri = to_int(.PRIORITY) ?? 6
    if pri <= 3 {
      lv = "ERROR"
    } else if pri == 4 {
      lv = "WARNING"
    } else if pri <= 6 {
      lv = "INFO"
    } else {
      lv = "DEBUG"
    }

    # OpenObserve's JSON ingest reads _timestamp in epoch MICROseconds.
    # Infallible chain for the 0.55 dialect: to_int(timestamp) cannot
    # fail (E651 fires if you coalesce it), timestamp*int can.
    ts_secs = to_int(to_unix_timestamp(.timestamp) ?? now())

    . = {
      "message": m,
      "host": h,
      "unit": u,
      "level": lv,
      "_timestamp": ts_secs * 1000000,
      "timestamp": to_string(.timestamp) ?? "",
    }

    if cn != "" {
      .container = cn
    }
  '';
in {
  options.services.homelab-log-shipper = {
    enable = lib.mkEnableOption "Vector journald → OpenObserve shipper";

    endpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://10.10.0.6:5080";
      description = ''
        OpenObserve base URL. The sink posts JSON events to
        <endpoint>/api/default/default/_json — OpenObserve's documented
        Vector integration path (basic auth = root user). The nixpkgs
        vector 0.55 `opentelemetry` sink's HTTP variant has an unstable
        cross-version schema (type/protocol/uri/encoding churn hit
        during the 2026-09-25 bring-up); the plain http sink is stable.
      '';
    };

    excludeUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "systemd units to exclude from shipping.";
    };
  };

  config = lib.mkMerge [
    # Importing the module opts the host in (beszel-agent pattern) — the
    # fleet ships its journal unless a host explicitly disables it.
    { services.homelab-log-shipper.enable = lib.mkDefault true; }

    (lib.mkIf cfg.enable {
      services.vector = {
        enable = true;
        journaldAccess = true;
        settings = {
          sources.journald = {
            type = "journald";
          } // lib.optionalAttrs (cfg.excludeUnits != [ ]) {
            exclude_units = cfg.excludeUnits;
          };

          transforms.journald_remap = {
            type = "remap";
            inputs = [ "journald" ];
            source = remap;
          };

          sinks.openobserve = {
            # Plain http sink → OpenObserve's JSON ingest (their documented
            # Vector integration). See the endpoint option for why not the
            # `opentelemetry` sink.
            type = "http";
            inputs = [ "journald_remap" ];
            uri = cfg.endpoint + "/api/default/default/_json";
            method = "post";
            compression = "gzip";
            encoding.codec = "json";
            auth = {
              strategy = "basic";
              # ${VAR:-default} keeps the nixpkgs module's build-time
              # `vector validate` green (no env at build); the real values
              # come from the EnvironmentFile at runtime.
              user = "\${ZO_ROOT_USER_EMAIL:-vector-validate}";
              password = "\${ZO_ROOT_USER_PASSWORD:-vector-validate}";
            };
            batch = {
              max_bytes = 4000000;
              timeout_secs = 10;
            };
            buffer = {
              type = "disk";
              max_size = 268435488; # 256 MiB — survive OpenObserve downtime
            };
            request.retry_max_duration_secs = 30;
          };
        };
      };

      age.secrets.openobserve-env.file = ../secrets/openobserve-env.age;

      # The nixpkgs vector module has no environmentFile option; attach the
      # agenix file directly so ${ZO_ROOT_USER_*} resolve at runtime.
      # systemd reads EnvironmentFile as root, so this also works for the
      # module's non-root vector user.
      systemd.services.vector.serviceConfig.EnvironmentFile =
        config.age.secrets.openobserve-env.path;
    })
  ];
}

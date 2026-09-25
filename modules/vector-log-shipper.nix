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
# VALIDATION GOTCHA (2026-09-25): the nixpkgs module's build-time
# `vector validate` derivation does NOT compile the VRL remap — two
# broken remaps passed `nix flake check` and failed at runtime (exit 78,
# which also aborts switch-to-configuration with exit 4 mid-activation).
# The real gate: `nix eval ...config.services.vector.settings --json`,
# convert to TOML, then `vector validate --no-environment` with the
# nixpkgs vector binary against that file.
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
    .message = to_string(.MESSAGE) ?? ""
    .host = to_string(._HOSTNAME) ?? ""

    u = to_string(._SYSTEMD_UNIT) ?? to_string(.SYSLOG_IDENTIFIER) ?? "unknown"
    .unit = replace(u, r'\.service$', "")

    if exists(.CONTAINER_NAME) {
      .container = to_string(.CONTAINER_NAME) ?? ""
    }

    pri = to_int(.PRIORITY) ?? 6
    if pri <= 3 {
      .level = "ERROR"
    } else if pri == 4 {
      .level = "WARNING"
    } else if pri <= 6 {
      .level = "INFO"
    } else {
      .level = "DEBUG"
    }

    # Drop raw journald metadata — the fields above are the queryable set.
    # (This VRL's del() takes ONE path per call, not an array.)
    del(.MESSAGE)
    del(.PRIORITY)
    del(._HOSTNAME)
    del(._SYSTEMD_UNIT)
    del(._COMM)
    del(._PID)
    del(._BOOT_ID)
    del(._MACHINE_ID)
    del(._RUNTIME_SCOPE)
    del(._TRANSPORT)
    del(._UID)
    del(._GID)
    del(._CAP_EFFECTIVE)
    del(._SELINUX_CONTEXT)
    del(._SOURCE_REALTIME_TIMESTAMP)
    del(.__REALTIME_TIMESTAMP)
    del(.__MONOTONIC_TIMESTAMP)
    del(.SYSLOG_FACILITY)
    del(.SYSLOG_IDENTIFIER)
    del(.CODE_FILE)
    del(.CODE_LINE)
    del(.CODE_FUNC)
    del(.ERRNO)
    del(.INVOCATION_ID)
    del(.CONTAINER_ID)
    del(.CONTAINER_ID_FULL)
    del(.CONTAINER_TAG)
    del(.CONTAINER_NAME)

    # OpenObserve's JSON ingest reads _timestamp in epoch MICROseconds;
    # without it, events land at ingest time. (to_unix_timestamp is
    # fallible — bind it with ?? before doing arithmetic.)
    ts = to_unix_timestamp(.timestamp) ?? now()
    ._timestamp = to_int(ts * 1000000)
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

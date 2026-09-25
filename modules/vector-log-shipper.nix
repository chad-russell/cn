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
    del([
      .MESSAGE, .PRIORITY, ._HOSTNAME, ._SYSTEMD_UNIT, ._COMM, ._PID,
      ._BOOT_ID, ._MACHINE_ID, ._RUNTIME_SCOPE, ._TRANSPORT, ._UID, ._GID,
      ._CAP_EFFECTIVE, ._SELINUX_CONTEXT, ._SOURCE_REALTIME_TIMESTAMP,
      .__REALTIME_TIMESTAMP, .__MONOTONIC_TIMESTAMP, .SYSLOG_FACILITY,
      .SYSLOG_IDENTIFIER, .CODE_FILE, .CODE_LINE, .CODE_FUNC, .ERRNO,
      .INVOCATION_ID, .CONTAINER_ID, .CONTAINER_ID_FULL, .CONTAINER_TAG,
      .CONTAINER_NAME,
    ])
  '';
in {
  options.services.homelab-log-shipper = {
    enable = lib.mkEnableOption "Vector journald → OpenObserve shipper";

    endpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://10.10.0.6:5080/api/default";
      description = ''
        OTLP/HTTP base endpoint (Vector appends /v1/logs). Includes the
        org path: OpenObserve serves OTLP at /api/<org>/v1/logs.
      '';
    };

    excludeUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "systemd units to exclude from shipping.";
    };
  };

  config = lib.mkIf cfg.enable {
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
          type = "otlp";
          inputs = [ "journald_remap" ];
          endpoint = cfg.endpoint;
          protocol = "http";
          compression = "gzip";
          auth = {
            strategy = "basic";
            user = "\${ZO_ROOT_USER_EMAIL}";
            password = "\${ZO_ROOT_USER_PASSWORD}";
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
  };
}

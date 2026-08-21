# ── DeepSeek Harness (dsh) agent web UI ──────────────────────────────
#
# Self-hosted DeepSeek Harness (github.com/deepseek-ai/deepseek-harness)
# serving its Web UI on bee. Uses the official npm distribution packaged
# at pkgs/dsh (buildNpmPackage).
#
# Exposure model (preserves dsh's own safety posture):
#   dsh web binds 127.0.0.1 ONLY — the CLI intentionally refuses
#   --host 0.0.0.0 because the web surface is agent-driven RCE by design
#   (shell + file tools). We keep that and bridge to Nebula externally:
#
#     dsh (127.0.0.1:3080)
#       ← systemd-socket-proxyd (10.10.0.12:3080, Nebula interface only)
#         ← bees Caddy  https://dsh.internal.crussell.io
#              (wildcard *.internal.crussell.io DNS + TLS already exist)
#
#   The proxy also satisfies dsh's /api browser-trust fence: the fence
#   validates the Host header authority, so dsh must be told to trust
#   `dsh.internal.crussell.io` via --trusted-host.
#
# Model backend: bees' llama.cpp server (Qwen3.8-27B-UD-Q6_K_XL with
# vision) over Nebula at http://10.10.0.6:8888/v1 — keyless custom
# provider `bees-llamacpp`. Compat flags are llama.cpp specifics from
# dsh's provider guide: no `developer` role, use `max_tokens`.
#
# Settings lifecycle: DSH_HOME=/var/lib/dsh is seeded ONCE with
# settings.yaml (provider + default model). Thereafter the file belongs
# to the running UI (dsh rewrites it when models change in Settings →
# Models) — do not edit while the service is running.

{ config, lib, pkgs, dsh, ... }:

let
  cfg = config.services.dsh;

  # dsh's loopback-only webserver; bridged to Nebula by socket-proxyd.
  port = 3080;

  # bee's Nebula address (lib/host-meta.nix is the source of truth).
  nebulaIp = "10.10.0.12";

  # Public hostname (bees Caddy route → this service).
  hostname = "dsh.internal.crussell.io";

  # bees llama.cpp endpoint over Nebula (llama-server@Qwen3.8 systemd unit).
  llamaBaseUrl = "http://10.10.0.6:8888/v1";
  llamaModel = "Qwen3.8-27B-UD-Q6_K_XL";

  seedSettings = (pkgs.formats.yaml { }).generate "settings.yaml" {
    llm-pi-ai = {
      providers.bees-llamacpp = {
        displayName = "bees llama.cpp";
        api = "openai-completions";
        baseURL = llamaBaseUrl;
        # llama-server is keyless, but pi-ai has no anonymous mode: a
        # request without any credential fails MISSING_CREDENTIAL. The
        # dummy value comes from the dsh-web unit environment (see
        # environment.BEES_LLAMACPP_API_KEY below); llama-server ignores
        # Authorization headers, so the wire is unchanged.
        apiKeyEnv = "BEES_LLAMACPP_API_KEY";
        defaultInput = [ "text" "image" ];
        compat = {
          supportsDeveloperRole = false;
          maxTokensField = "max_tokens";
        };
        models = [{
          id = llamaModel;
          contextWindow = 131072; # match bees llama-server -c (128K)
          # Canonical form per providers.md: per-model input, not just
          # the route-level defaultInput fallback.
          input = [ "text" "image" ];
        }];
      };
    };
    agent-default-model = {
      provider = "bees-llamacpp";
      model = llamaModel;
    };
  };

in {
  options.services.dsh = {
    enable = lib.mkEnableOption "DeepSeek Harness web UI";
    # dsh arrives as a specialArg from flake.nix (dshPkg); the package
    # is not in nixpkgs.
    package = lib.mkOption {
      type = lib.types.package;
      default = dsh;
      description = "dsh package (flake pkgs/dsh via specialArg).";
    };
  };

  config = lib.mkIf cfg.enable {
    # dsh's local sandbox probes PATH for bwrap at tool-run time.
    environment.systemPackages = [ cfg.package pkgs.bubblewrap ];

    # ── State + seed ───────────────────────────────────────────────
    systemd.tmpfiles.rules = [ "d /var/lib/dsh 0700 crussell users -" ];

    systemd.services.dsh-seed = {
      description = "Seed dsh settings (first boot only)";
      wantedBy = [ "multi-user.target" ];
      before = [ "dsh-web.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "crussell";
        Group = "users";
      };
      unitConfig.ConditionPathExists = "!/var/lib/dsh/settings.yaml";
      script = ''
        install -D -m 0600 ${seedSettings} /var/lib/dsh/settings.yaml
      '';
    };

    # ── Web service ────────────────────────────────────────────────
    systemd.services.dsh-web = {
      description = "DeepSeek Harness web UI (dsh web)";
      wants = [ "dsh-seed.service" ];
      after = [ "network-online.target" "dsh-seed.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "crussell";
        Group = "users";
        WorkingDirectory = "/home/crussell";
        ExecStart = "${cfg.package}/bin/dsh web --port ${toString port} --no-open --trusted-host ${hostname}";
        Restart = "on-failure";
        RestartSec = "5";
      };
      environment.DSH_HOME = "/var/lib/dsh";
      # The harness resolves `bash`, `bwrap`, and user commands by bare name
      # (PATH lookup). The systemd default unit PATH contains none of them:
      # the bwrap sandbox probe fails ENOENT and landlock-run's exec of the
      # command fails ENOENT → "no sandbox backend is usable". Point PATH at
      # the system profile (bash, bwrap, git, and everything else on bee).
      environment.PATH = "/run/current-system/sw/bin";
      # Credential for the keyless bees llama.cpp route (see apiKeyEnv in
      # the seed): non-empty placeholder so pi-ai's credential resolution
      # succeeds; llama-server never checks it.
      environment.BEES_LLAMACPP_API_KEY = "keyless-llamacpp";
    };

    # ── Nebula exposure via systemd socket proxy ───────────────────
    # dsh binds loopback only by design. A socket unit on the Nebula IP
    # with systemd-socket-proxyd gives bees Caddy a stable target
    # without fighting dsh's bind policy. listen stream on Nebula IP
    # means the proxy is unreachable from the LAN/public side.
    systemd.sockets."dsh-web-proxy" = {
      description = "Nebula socket for dsh web proxy";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = "${nebulaIp}:${toString port}";
        BindIPv6Only = "both";
      };
    };

    systemd.services."dsh-web-proxy" = {
      description = "Socket proxy: Nebula ${nebulaIp}:${toString port} → dsh loopback";
      requires = [ "dsh-web.service" ];
      after = [ "dsh-web.service" ];
      serviceConfig = {
        TriggerLimitIntervalSec = "1s";
        TriggerLimitBurst = "10000";
        ExecStart =
          "${config.systemd.package}/lib/systemd/systemd-socket-proxyd 127.0.0.1:${toString port}";
      };
    };
  };
}

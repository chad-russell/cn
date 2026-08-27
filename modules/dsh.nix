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
# Model backends (mirrors the Hermes model set in
# hosts/bee/configuration.nix):
#   bees-llamacpp  local Qwen3.8-27B on bees over Nebula (default)
#   gloo           employer-paid platform, WORK ONLY — hand-declared
#                  catalog (the platform 403s /models), no compat
#                  overrides: developer role + max_completion_tokens
#                  + tool calls all verified accepted 2026-08-25
#   openrouter     catalog route — inherits pi-ai's full OpenRouter
#                  model catalog; personal fallback provider
#
# Settings lifecycle: DSH_HOME=/var/lib/dsh is seeded ONCE with
# settings.yaml (providers + default model). Thereafter the file belongs
# to the running UI (dsh rewrites it when models change in Settings →
# Models) — do not edit while the service is running. Re-seeding after a
# catalog change means: stop dsh-web + dsh-seed, remove settings.yaml,
# activate (dsh-seed's ConditionPathExists gate re-opens).

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

  # Gloo platform (employer-paid, WORK ONLY — never for personal tasks).
  # Direct to platform.ai.gloo.com; the self-hosted proxy on bees is
  # retired. /models is forbidden, so the catalog is hand-declared —
  # same model set as Hermes' gloo provider (hosts/bee/configuration.nix),
  # minus supports_vision flags (pi-ai pricing/modalities ride the
  # installed entry or are absent — no harness consumer).
  glooBase = "https://platform.ai.gloo.com/ai/v2";
  # contextWindow/maxTokens per model, sourced from pi-ai's pinned
  # OpenRouter catalog (same upstream vendor models) where an exact-id
  # match exists; sensible defaults otherwise. These are advisory
  # sizing, not hard caps.
  glooModels = [
    {
      id = "gloo-anthropic-claude-opus-5";
      contextWindow = 1000000;
      maxTokens = 128000;
    }
    {
      id = "gloo-anthropic-claude-opus-4.8";
      contextWindow = 1000000;
      maxTokens = 128000;
    }
    {
      id = "gloo-anthropic-claude-sonnet-4.6";
      contextWindow = 1000000;
      maxTokens = 128000;
    }
    {
      id = "gloo-anthropic-claude-haiku-4.5";
      contextWindow = 200000;
      maxTokens = 64000;
    }
    {
      id = "gloo-openai-gpt-5.5";
      contextWindow = 1050000;
      maxTokens = 128000;
    }
    {
      id = "gloo-openai-gpt-5.4";
      contextWindow = 1050000;
      maxTokens = 128000;
    }
    {
      id = "gloo-openai-gpt-5.2";
      contextWindow = 400000;
      maxTokens = 128000;
    }
    {
      id = "gloo-openai-gpt-5.1";
      contextWindow = 400000;
      maxTokens = 128000;
    }
    {
      id = "gloo-openai-gpt-5.3-codex";
      contextWindow = 400000;
      maxTokens = 128000;
    }
    {
      id = "gloo-google-gemini-3.5-flash";
      contextWindow = 1048576;
      maxTokens = 65536;
    }
    {
      id = "gloo-google-gemini-3.1-pro";
      contextWindow = 1048576;
      maxTokens = 65536;
    }
    {
      id = "gloo-google-gemini-2.5-pro";
      contextWindow = 1048576;
      maxTokens = 65536;
    }
    {
      id = "gloo-deepseek-v4-pro";
      contextWindow = 1048576;
      maxTokens = 384000;
    }
    {
      id = "gloo-deepseek-v4-flash";
      contextWindow = 1048575;
      maxTokens = 4096;
    }
    {
      id = "gloo-xai-grok-4.5";
      contextWindow = 500000;
      maxTokens = 4096;
    }
    {
      id = "gloo-qwen-3.7-max";
      contextWindow = 1000000;
      maxTokens = 65536;
    }
    {
      id = "gloo-qwen-3-coder";
      contextWindow = 262144;
      maxTokens = 65536;
    }
    {
      id = "gloo-kimi-k3";
      contextWindow = 1048576;
      maxTokens = 131072;
    }
    {
      id = "gloo-z-ai-glm-5.2";
      contextWindow = 1048576;
      maxTokens = 131072;
    }
    {
      id = "gloo-minimax-m3";
      contextWindow = 524288;
      maxTokens = 512000;
    }
    {
      id = "gloo-mistral-large-3";
      contextWindow = 262144;
      maxTokens = 4096;
    }
  ];

  seedSettings = (pkgs.formats.yaml { }).generate "settings.yaml" {
    llm-pi-ai = {
      providers = {
        bees-llamacpp = {
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
        # Hand-declared Gloo route (pi-ai ships nothing under "gloo").
        # No compat overrides: the platform accepts the developer role,
        # max_completion_tokens, and tool calls (verified 2026-08-25).
        # Credential via EnvironmentFile gloo-api-key (see below) —
        # WORK ONLY, employer-paid.
        gloo = {
          displayName = "Gloo (work)";
          api = "openai-completions";
          baseURL = glooBase;
          apiKeyEnv = "GLOO_API_KEY";
          models = glooModels;
        };
        # Catalog route: pi-ai ships a full OpenRouter provider (276
        # models), so only the credential reference is needed — the
        # endpoint, wire protocol, and model catalog all come from
        # pi-ai's installed catalog.
        openrouter = { apiKeyEnv = "OPENROUTER_API_KEY"; };
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

    # Provider credentials (same .age files opencode.nix uses; equal
    # definitions from both modules merge cleanly). gloo-api-key's
    # first NixOS consumer is here; login shells read the same value
    # via the server-shell zshenv pattern.
    age.secrets.gloo-api-key.file = ../secrets/gloo-api-key.age;
    age.secrets.openrouter-api-key.file = ../secrets/openrouter-api-key.age;

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
        ExecStart = "${cfg.package}/bin/dsh web --port ${
            toString port
          } --no-open --trusted-host ${hostname}";
        # GLOO_API_KEY (gloo route) + OPENROUTER_API_KEY (openrouter
        # route), resolved per request via the settings.yaml apiKeyEnv
        # references. Same .age sources as the zshenv login-shell
        # pattern (modules/server-shell.nix).
        EnvironmentFile = [
          config.age.secrets.gloo-api-key.path
          config.age.secrets.openrouter-api-key.path
        ];
        Restart = "on-failure";
        RestartSec = "5";
      };
      environment.DSH_HOME = "/var/lib/dsh";
      # The harness resolves `bash`, `bwrap`, and user commands by bare name
      # (PATH lookup). The systemd default unit PATH contains none of them:
      # the bwrap sandbox probe fails ENOENT and landlock-run's exec of the
      # command fails ENOENT → "no sandbox backend is usable". Point PATH at
      # the system profile (bash, bwrap, git, and everything else on bee).
      environment.PATH = lib.mkForce "/run/current-system/sw/bin";
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
      description =
        "Socket proxy: Nebula ${nebulaIp}:${toString port} → dsh loopback";
      requires = [ "dsh-web.service" ];
      after = [ "dsh-web.service" ];
      serviceConfig = {
        TriggerLimitIntervalSec = "1s";
        TriggerLimitBurst = "10000";
        ExecStart =
          "${config.systemd.package}/lib/systemd/systemd-socket-proxyd 127.0.0.1:${
            toString port
          }";
      };
    };
  };
}

# ── Buzz agent harness (buzz-acp) ───────────────────────────────────────
#
# Runs one `buzz-acp` systemd service per declared agent. Each service connects
# (outbound only — no inbound ports) to the hosted Buzz relay, authenticates as
# its agent identity, and spawns the chosen agent runtime (buzz-agent by
# default) to answer @mentions from any client (phone/laptop).
#
# Shape mirrors modules/opencode.nix: agenix EnvironmentFiles + Restart=always.
#
# Agent identity keys (BUZZ_PRIVATE_KEY) live in per-agent agenix env files.
# Provider API keys are referenced from the shared secrets on the host
# (zai-api-key → ZHIPU_API_KEY, openrouter-api-key → OPENROUTER_API_KEY).
#
# Minimal host wiring (hosts/bee/configuration.nix):
#
#   services.buzz-harness = {
#     enable = true;
#     agents.bumble = {
#       privateKeySecret = "buzz-agent-bumble-env";
#       provider = "openai";
#       model = "glm-5.2";
#       extraEnv = {
#         OPENAI_COMPAT_BASE_URL = "https://api.z.ai/api/coding/paas/v4";
#         OPENAI_COMPAT_API = "chat";
#       };
#       environmentFiles = [
#         config.age.secrets.zai-api-key.path
#       ];
#     };
#   };

{ config, lib, pkgs, buzz, ... }:

let
  cfg = config.services.buzz-harness;
  agentOpts = { name, ... }: {
    options = {
      privateKeySecret = lib.mkOption {
        type = lib.types.str;
        description = ''
          Name of the agenix secret (relative to secrets/) whose env file
          contains at least `BUZZ_PRIVATE_KEY=<nsec-or-hex>` for this agent.
        '';
      };

      runtime = lib.mkOption {
        type = lib.types.str;
        default = "buzz-agent";
        description = ''
          Agent binary buzz-acp spawns. `buzz-agent` (native, default) or e.g.
          `opencode` (then set runtimeArgs = ["acp"]).
        '';
      };

      runtimeArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Args passed to the runtime binary (e.g. [\"acp\"] for opencode).";
      };

      provider = lib.mkOption {
        type = lib.types.str;
        default = "openai";
        description = ''
          For buzz-agent: BUZZ_AGENT_PROVIDER. `openai` (any OpenAI-compatible
          endpoint incl. Z.AI), `openrouter`, `anthropic`, `databricks`.
        '';
      };

      model = lib.mkOption {
        type = lib.types.str;
        default = "glm-5.2";
        description = ''
          For buzz-agent: model id. With provider=openai this is
          OPENAI_COMPAT_MODEL; with openrouter, OPENROUTER_MODEL.
        '';
      };

      extraEnv = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = ''
          Non-secret per-agent env (e.g. OPENAI_COMPAT_BASE_URL,
          OPENAI_COMPAT_API). Secret values belong in environmentFiles.
        '';
      };

      environmentFiles = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [ ];
        description = ''
          agenix secret paths whose env vars are injected at spawn time
          (e.g. provider API keys like ZHIPU_API_KEY / OPENROUTER_API_KEY).
        '';
      };

      apiKeyEnvFrom = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          If the provider key is exposed under a name buzz-agent doesn't expect,
          set this to the source env var; the service remaps it onto the
          provider's key var at launch. e.g. for Z.AI via the shared
          zai-api-key secret: apiKeyEnvFrom = "ZHIPU_API_KEY" (which gets
          exported as OPENAI_COMPAT_API_KEY for provider=openai).
        '';
      };

      extraOptions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra buzz-acp CLI flags (e.g. [\"--agents\" \"2\"]).";
      };
    };
  };
in
{
  options.services.buzz-harness = {
    enable = lib.mkEnableOption "Buzz agent harness (buzz-acp)";

    package = lib.mkOption {
      type = lib.types.package;
      default = buzz;
      description = "Buzz CLI stack package (provides buzz-acp, buzz-cli, buzz-agent).";
    };

    relayUrl = lib.mkOption {
      type = lib.types.str;
      default = "wss://crussell.communities.buzz.xyz";
      description = "Buzz relay WebSocket URL.";
    };

    agents = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule agentOpts);
      default = { };
      description = "Agent identities to run, keyed by service name.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Require every agent's nsec secret to be declared on the host. The host
    # (or a shared module) must add matching `age.secrets.<name>.file` entries.
    age.secrets = lib.mapAttrs' (_: a:
      lib.nameValuePair a.privateKeySecret {
        file = ../secrets/${a.privateKeySecret}.age;
      }
    ) cfg.agents;

    systemd.services = lib.mapAttrs' (name: a:
      let
        # buzz-agent reads the API key from a provider-specific env var. Map
        # from a host secret exposed under a different name (e.g. ZHIPU_API_KEY)
        # onto the one the agent expects, so one shared secret serves both
        # opencode (ZHIPU_API_KEY) and buzz-agent (OPENAI_COMPAT_API_KEY).
        agentKeyVar = {
          openai = "OPENAI_COMPAT_API_KEY";
          openrouter = "OPENROUTER_API_KEY";
          anthropic = "ANTHROPIC_API_KEY";
        }.${a.provider} or null;
        # NOTE: use the braceless $VAR form — Nix would otherwise try to
        # interpolate a literal "${...}" in the generated bash.
        keyExport = lib.optionalString (agentKeyVar != null && a.apiKeyEnvFrom != null)
          ("export " + agentKeyVar + "=\"$" + a.apiKeyEnvFrom + "\"");
        startScript = pkgs.writeShellScriptBin "buzz-acp-${name}" ''
          ${keyExport}
          exec ${cfg.package}/bin/buzz-acp ${lib.escapeShellArgs a.extraOptions}
        '';
      in
      lib.nameValuePair "buzz-acp-${name}" {
        description = "Buzz ACP harness — agent ${name}";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        # buzz-cli + buzz-agent come from the package (NixOS appends /bin).
        # Add the system profile so an opencode runtime agent resolves too.
        path = [
          cfg.package
          "/run/current-system/sw"
        ];

        environment = {
          BUZZ_RELAY_URL = cfg.relayUrl;
          BUZZ_ACP_AGENT_COMMAND = a.runtime;
          # Passed to the spawned agent binary (comma-separated). Empty for
          # buzz-agent; "acp" for opencode. Setting it explicitly overrides
          # buzz-acp's built-in "acp" default so buzz-agent gets no stray args.
          BUZZ_ACP_AGENT_ARGS = lib.concatStringsSep "," a.runtimeArgs;
          # buzz-agent provider config (harmless when runtime != buzz-agent).
          BUZZ_AGENT_PROVIDER = a.provider;
          HOME = "/home/crussell";
        }
        // (lib.optionalAttrs (a.runtime == "buzz-agent") (
          if a.provider == "openrouter" then { OPENROUTER_MODEL = a.model; }
          else if a.provider == "anthropic" then { ANTHROPIC_MODEL = a.model; }
          else { OPENAI_COMPAT_MODEL = a.model; }
        ))
        // a.extraEnv;

        serviceConfig = {
          Type = "simple";
          # Run as the real user (like modules/opencode.nix) so an opencode
          # runtime agent can read ~/.config/opencode, and so the same agenix
          # EnvironmentFile pattern works. systemd reads EnvironmentFile as
          # root, so the service user need not own the secrets.
          User = "crussell";
          Group = "users";
          WorkingDirectory = "/home/crussell";
          # nsec (BUZZ_PRIVATE_KEY) + provider keys.
          EnvironmentFile = [ config.age.secrets.${a.privateKeySecret}.path ] ++ a.environmentFiles;
          # extraOptions are buzz-acp's own CLI flags (e.g. ["--agents" "2"]).
          # The wrapper remaps the provider key env var (see apiKeyEnvFrom).
          ExecStart = "${startScript}/bin/buzz-acp-${name}";
          Restart = "always";
          RestartSec = "5";
          StartLimitIntervalSec = "60";
          StartLimitBurst = "5";
        };
      }
    ) cfg.agents;
  };
}

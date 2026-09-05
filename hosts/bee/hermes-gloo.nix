# ── bee: Hermes 'gloo' profile gateway (work lane) ─────────────────
#
# Work instance of Hermes on bee — serves Chad's employer work
# (Wycliffe/360: GPL, Polymer, Hummingbird, open-bible, QR codes, RFCs).
# Runs the ORIGINAL 'hermes' Discord bot (app 1544082952290566235), pinned
# to #gloo-work (1544085937577918535) via allowed_channels in the profile
# config.yaml; Discord permission overwrites deny it VIEW_CHANNEL on every
# personal category (Chad flipped these at the 2026-09-04 Glen/Gloo split).
#
# The everything-else instance is the DEFAULT profile (hermes-agent.service,
# "Glen", running the hermes-private bot). Kanban boards are shared across
# profiles (kanban/ lives in the default root) — the htb loop's workers and
# watchdog cron stay functional from either side.
#
# Isolation guarantees (vs default/glen):
#   - separate HERMES_HOME → separate state.db, sessions, memories/, skills/
#   - mem0 IS enabled (memory.provider "mem0", declared below) but isolated
#     from glen's memory: the profile's own $HERMES_HOME/mem0.json points at
#     a SEPARATE qdrant collection 'mem0-gloo' with user_id 'chad-gloo'
#     (both profiles share the loopback qdrant server 127.0.0.1:6333, which
#     is safe — server mode has no cross-instance folder lock). mem0.json is
#     deliberately NOT nix-managed; it lives in the profile home.
#   - NO dashboard secrets in its env (serve stays glen-only)
#   - env from agenix: secrets/hermes-gloo-env.age (ZAI_CODING_KEY,
#     OPENROUTER_API_KEY, GLOO_API_KEY, original DISCORD_BOT_TOKEN,
#     DISCORD_ALLOWED_USERS). NEVER load hermes-bee-env-glen.age here — the
#     private bot token would win/trip Hermes' bot-token lock.
#
# Declarative config (2026-09-05): the memory keys below are Nix-owned and
# deep-merged into $glooHome/config.yaml at every activation, using the SAME
# machinery as the upstream hermes-agent module uses for glen (pinned flake
# input renders toJSON → YAML and merges: Nix keys replace the same keys on
# disk, every runtime-owned key — model picks, custom_providers, mcp_servers,
# gateway.platforms, `hermes config set` results — survives the merge).
# The hand-rolled unit below stays: same ExecStart/env/EnvironmentFile.
{ config, lib, pkgs, hermes-agent, ... }:

let
  glooHome = "/var/lib/hermes/.hermes/profiles/gloo";

  # Exactly the keys this module owns. Anything else in the live config.yaml
  # is runtime-owned and must survive activation untouched.
  glooSettings = {
    memory = {
      provider = "mem0";
      memory_char_limit = 6000;
      user_char_limit = 2000;
    };
  };

  # Same renderer + merge script as upstream (nix/moduleCommon.nix): toJSON
  # output is valid YAML, and the pinned input's configMergeScript.nix
  # (python3 + pyyaml) overlays the Nix keys onto the file on disk.
  glooConfigGenerated =
    pkgs.writeText "hermes-gloo-config.yaml" (builtins.toJSON glooSettings);
  glooConfigMerge =
    pkgs.callPackage (hermes-agent + "/nix/configMergeScript.nix") { };
in {
  systemd.services.hermes-gloo-gateway = {
    description = "Hermes Agent Gateway (gloo work profile)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    environment = {
      HERMES_HOME = glooHome;
      HOME = "/home/crussell";
      # Restart trigger: the store path changes whenever the declared
      # settings above change, which rewrites the unit text and makes
      # switch-to-configuration bounce the gateway so it picks up the new
      # config.yaml (hermes caches config at process start).
      HERMES_GLOO_DECLARED_CONFIG = glooConfigGenerated;
      # 2026-09-05: user-session env for systemd-run --user --scope — see
      # the identical fix on hermes-agent in configuration.nix (cron /
      # background-child dispatch dies without it on hermes ≥0.21).
      XDG_RUNTIME_DIR = "/run/user/1000";
      DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/1000/bus";
      SHELL = "${pkgs.bashInteractive}/bin/bash";
      PATH = lib.mkForce
        "/run/wrappers/bin:${pkgs.bashInteractive}/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin";
    };

    serviceConfig = {
      Type = "simple";
      User = "crussell";
      Group = "hermes";
      WorkingDirectory = "/home/crussell";
      ExecStart =
        "/run/current-system/sw/bin/hermes gateway run --replace --external-supervisor";
      EnvironmentFile = [ config.age.secrets.hermes-gloo-env.path ];
      Restart = "on-failure";
      RestartSec = 10;
      UMask = "0007";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = false;
      ProtectSystem = false;
    };
  };

  # Deep-merge the declared settings into the profile's config.yaml at
  # activation (runs before switch-to-configuration restarts the gateway).
  # Activation runs as root and python rewrites the file in place, so
  # ownership/mode are set explicitly afterwards (a fresh file would
  # otherwise be root-owned).
  system.activationScripts.hermes-gloo-config =
    lib.stringAfter [ "users" "groups" ] ''
      mkdir -p ${glooHome}
      ${glooConfigMerge} ${glooConfigGenerated} ${glooHome}/config.yaml
      chown crussell:hermes ${glooHome}/config.yaml
      chmod 660 ${glooHome}/config.yaml
    '';
}

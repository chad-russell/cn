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
#   - NO mem0 (memory.provider "" in profile config.yaml) — personal
#     qdrant/mem0 is untouchable from work
#   - NO dashboard secrets in its env (serve stays glen-only)
#   - env from agenix: secrets/hermes-gloo-env.age (ZAI_CODING_KEY,
#     OPENROUTER_API_KEY, GLOO_API_KEY, original DISCORD_BOT_TOKEN,
#     DISCORD_ALLOWED_USERS). NEVER load hermes-bee-env-glen.age here — the
#     private bot token would win/trip Hermes' bot-token lock.
{ config, lib, pkgs, ... }:

{
  systemd.services.hermes-gloo-gateway = {
    description = "Hermes Agent Gateway (gloo work profile)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    environment = {
      HERMES_HOME = "/var/lib/hermes/.hermes/profiles/gloo";
      HOME = "/home/crussell";
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
}

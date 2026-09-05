# ── bee: Hermes 'personal' profile gateway ─────────────────────────
#
# Always-on gateway for the 'personal' profile — Chad's private personal
# lane (own state.db, memory, skills, cron under
# /var/lib/hermes/.hermes/profiles/personal; see that directory's
# SOUL.md for the lane rules). Runs the hermes-private Discord bot
# (app 1545187919961129123), confined to the "Private" category in the
# Glen server via Discord permission overwrites: the main bot (hermes,
# app 1544082952290566235) has a member-level VIEW_CHANNEL deny there,
# and this bot is denied VIEW_CHANNEL on the public categories. The
# gateway adapter respects those overwrites — it only receives events
# for channels it can see.
#
# Isolation guarantees (vs the default profile / hermes-agent.service):
#   - separate HERMES_HOME → separate state.db, sessions, memories/,
#     skills/, cron/, channel_directory
#   - NO mem0 (memory.provider "" in the profile config.yaml) — the
#     default profile's qdrant collection + mem0 user_id stay untouchable
#   - NO gloo provider, NO work MCP servers, NO homelab skills
#   - profile .env holds its own DISCORD_BOT_TOKEN; this unit must NOT
#     load secrets/hermes-bee-env.age (it carries the MAIN bot token,
#     which would win over dotenv and trip Hermes' bot-token lock)
#   - terminal.cwd = /home/crussell/personal (0700, outside ~/Code and
#     ~/Gloo)
#
# The unit is gated on a marker file (DISCORD_TOKEN_PRESENT in the
# profile dir): absent until the bot token is written to the profile
# .env, then `touch`ed once — after which the gateway starts on every
# boot without further manual steps.
{
  # RETIRED at the 2026-09-04 Glen/Gloo split: the personal profile's 11
  # sessions were merged into the DEFAULT profile (Glen = everything-else,
  # now running the hermes-private bot), and this unit's lane is served by
  # hermes-agent.service with hermes-bee-env-glen.age. Disabled (not
  # deleted) for one rollback cycle; delete this file + its import after
  # the split is verified. If it ever started alongside the default
  # gateway, BOTH would present the same bot token → lock conflict.
  systemd.services.hermes-personal-gateway = {
    description = "Hermes Agent Gateway (personal profile) [RETIRED]";
    wantedBy = lib.mkForce [ ];  # never auto-start
    # Auto-start at boot, but ONLY once the Discord token is in place:
    # the condition marker is touched when DISCORD_BOT_TOKEN is added to
    # the profile .env. Until then systemd cleanly SKIPS the unit
    # (condition not met — no crash-looping adapter on every boot).
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig.ConditionPathExists =
      "/var/lib/hermes/.hermes/profiles/personal/DISCORD_TOKEN_PRESENT";

    environment = {
      # Point HERMES_HOME directly at the profile dir (equivalent to
      # `hermes -p personal`; avoids profile-of-profile resolution).
      HERMES_HOME = "/var/lib/hermes/.hermes/profiles/personal";
      HOME = "/home/crussell";
      # bash-native subprocess lanes (same rationale as hermes-serve:
      # hermes' wrapper is bash-engineered; zsh globbing breaks it).
      SHELL = "${pkgs.bashInteractive}/bin/bash";
      PATH = lib.mkForce
        "/run/wrappers/bin:${pkgs.bashInteractive}/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin";
    };

    serviceConfig = {
      Type = "simple";
      User = "crussell";
      Group = "hermes";
      WorkingDirectory = "/home/crussell/personal";
      ExecStart =
        "/run/current-system/sw/bin/hermes gateway run --replace --external-supervisor";
      # Profile-local env (ZAI_CODING_KEY, OPENROUTER_API_KEY,
      # DISCORD_BOT_TOKEN, DISCORD_ALLOWED_USERS). Read by systemd as
      # root pre-drop so the provider resolver sees keys at startup
      # (same ordering rationale as the main gateway's agenix inject).
      EnvironmentFile =
        [ "/var/lib/hermes/.hermes/profiles/personal/.env" ];
      Restart = "on-failure";
      RestartSec = 10;
      UMask = "0007";
      NoNewPrivileges = true;
      PrivateTmp = true;
      # Full filesystem access as crussell (same posture as the main
      # gateway — this is an agent with terminal tools by design).
      ProtectHome = false;
      ProtectSystem = false;
    };
  };
}

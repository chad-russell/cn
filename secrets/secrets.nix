let
  # Age public key for crussell (private key at ~/.config/age/key.txt)
  crussell = "age1uhmefj4e0jhf4nza9efsdz9qa8fq08sf04c3jh268cf3uhmlypfqh60u2v";
in {
  "aws-env.age".publicKeys = [ crussell ];
  # ── OpenRouter API key (opencode) ─────────────────────────────
  "openrouter-api-key.age".publicKeys = [ crussell ];

  # ── Z.AI API key (opencode) ───────────────────
  "zai-api-key.age".publicKeys = [ crussell ];

  # ── Restic backup secrets ──────────────────────────────────────
  # S3 credentials (shared by all machines)
  "restic-s3-credentials.age".publicKeys = [ crussell ];
  # Per-machine restic repo passwords
  "restic-password-bees.age".publicKeys = [ crussell ];
  "restic-password-bee.age".publicKeys = [ crussell ];
  "restic-password-think.age".publicKeys = [ crussell ];

  # ── Gloo AI platform direct access ──────────────────────────────
  # GLOO_API_KEY for direct-to-platform work sessions (opencode on bees,
  # login shells via the age-decrypt zshenv pattern) AND for the Hermes
  # gateway's gloo provider (same value folded into
  # hermes-bee-env-glen.age at the 2026-09-06 single-brain collapse).
  "gloo-api-key.age".publicKeys = [ crussell ];

  # ── Beszel monitoring ──────────────────────────────────────────
  # Env file (KEY=<hub public key>, TOKEN=<universal token>) shared by
  # every beszel-agent. Created after first booting the hub.
  "beszel-agent-env.age".publicKeys = [ crussell ];

  # ── Kan (kan.bn) on bees — trello.crussell.io ────────────────────
  # POSTGRES_PASSWORD, POSTGRES_URL, BETTER_AUTH_SECRET, KAN_ADMIN_API_KEY.
  "kan-env.age".publicKeys = [ crussell ];

  # ── Lane (self-hosted Plane CE) on bees — lane.internal.crussell.io ──
  # SECRET_KEY, LIVE_SERVER_SECRET_KEY, POSTGRES_PASSWORD, DATABASE_URL,
  # REDIS_URL, AMQP_URL, RABBITMQ_DEFAULT_PASS, AWS_ACCESS_KEY_ID,
  # AWS_SECRET_ACCESS_KEY, WEBHOOK_ALLOWED_IPS.
  "lane-env.age".publicKeys = [ crussell ];

  # ── Proton Pass agent token for bee ("Glen" vault) ───────────────
  # PROTON_PASS_PERSONAL_ACCESS_TOKEN (hermes-bee agent, 6m expiry — renew via
  # pass-cli agent renew) + PROTON_PASS_ENCRYPTION_KEY (env key provider for
  # headless pass-cli). Deployed 0440 group=hermes so agent shells (user
  # crussell) can source it directly without sudo.
  "proton-pass-env.age".publicKeys = [ crussell ];

  # ── Hermes Agent gateway on bee (single brain: Glen, all lanes) ─
  # 2026-09-06 single-brain collapse: the gloo work profile/bot was
  # retired; the default gateway serves personal + work lanes with one
  # bot (hermes-glen). This env carries its token plus GLOO_API_KEY
  # (work provider). Historical name kept to avoid re-encrypting.
  "hermes-bee-env-glen.age".publicKeys = [ crussell ];

  # ── Hermes WebUI on bee ─────────────────────────────────────────
  # HERMES_WEBUI_PASSWORD for the web login gate at
  # https://hermes.internal.crussell.io (routed by bees Caddy to bee).
  # Retired 2026-09-01: hermes webui (desktop + Discord are the only surfaces).
  # "hermes-webui-env.age".publicKeys = [ crussell ];

  # ── Hermes Agent CLI/TUI/Desktop on thinkpad (retired 2026-09-08, HML-9) ──
  # Was OPENAI_API_KEY=<Z.AI coding key> for a local thinkpad agent install;
  # thinkpad is desktop-only now (talks to bee over SSH, no local provider
  # keys). No NixOS host consumed it. If a local agent ever returns, re-add
  # here + re-create the .age file; the thinkpad .zshenv decrypt loop and
  # hermes-desktop wrapper pick it back up unchanged.
}

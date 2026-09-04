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
  # after the self-hosted gloo proxy was retired). Same key value as the
  # GLOO_API_KEY line inside hermes-bee-env.age on bee.
  "gloo-api-key.age".publicKeys = [ crussell ];

  # ── Beszel monitoring ──────────────────────────────────────────
  # Env file (KEY=<hub public key>, TOKEN=<universal token>) shared by
  # every beszel-agent. Created after first booting the hub.
  "beszel-agent-env.age".publicKeys = [ crussell ];

  # ── Kan (kan.bn) on bees — trello.crussell.io ────────────────────
  # POSTGRES_PASSWORD, POSTGRES_URL, BETTER_AUTH_SECRET, KAN_ADMIN_API_KEY.
  "kan-env.age".publicKeys = [ crussell ];

  # ── Hermes Agent gateway on bee ───────────────────────────────
  # Combined env: OPENAI_API_KEY (Z.AI key remapped for Hermes'
  # OpenAI-compatible provider) + TELEGRAM_BOT_TOKEN + dashboard-auth
  # secrets. (Legacy BUZZ_* keys may linger inside; they are unused.)
  "hermes-bee-env.age".publicKeys = [ crussell ];

  # ── Hermes WebUI on bee ─────────────────────────────────────────
  # HERMES_WEBUI_PASSWORD for the web login gate at
  # https://hermes.internal.crussell.io (routed by bees Caddy to bee).
  # Retired 2026-09-01: hermes webui (desktop + Discord are the only surfaces).
  # "hermes-webui-env.age".publicKeys = [ crussell ];

  # ── Hermes Agent CLI/TUI/Desktop on thinkpad ───────────────────
  # OPENAI_API_KEY=<Z.AI coding key> so Hermes' OpenAI-compatible provider
  # resolver finds it. Same key value as zai-api-key.age (which exports it
  # under ZHIPU_API_KEY for opencode); remapped to OPENAI_API_KEY for Hermes.
  # Sourced into shells via dotfiles/.zshenv (age-decrypt on login) and into
  # the GUI desktop app via the ~/.local/bin/hermes-desktop wrapper.
  "hermes-thinkpad-env.age".publicKeys = [ crussell ];

  # ── searx-secret (retired 2026-09-03) ───────────────────────────
  # Removed with the SearXNG service (hosts/bee/searxng.nix deleted);
  # was the Flask session-signing key for the localhost searx instance.
  # secrets/searx-secret.age left on disk until agenix re-encrypt is run.
}

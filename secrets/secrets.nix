let
  # Age public key for crussell (private key at ~/.config/age/key.txt)
  crussell = "age1uhmefj4e0jhf4nza9efsdz9qa8fq08sf04c3jh268cf3uhmlypfqh60u2v";
in
{
  "aws-env.age".publicKeys = [ crussell ];
  # ── OpenRouter API key (opencode) ─────────────────────────────
  "openrouter-api-key.age".publicKeys = [ crussell ];

  # ── Z.AI API key (opencode + hermes agent) ───────────────────
  "zai-api-key.age".publicKeys = [ crussell ];

  # ── Restic backup secrets ──────────────────────────────────────
  # S3 credentials (shared by all machines)
  "restic-s3-credentials.age".publicKeys = [ crussell ];
  # Per-machine restic repo passwords
  "restic-password-bees.age".publicKeys = [ crussell ];
  "restic-password-bee.age".publicKeys = [ crussell ];
  "restic-password-think.age".publicKeys = [ crussell ];

  # ── Gloo AI proxy credentials ─────────────────────────────────
  "gloo-credentials.age".publicKeys = [ crussell ];

  # ── Beszel monitoring ──────────────────────────────────────────
  # Env file (KEY=<hub public key>, TOKEN=<universal token>) shared by
  # every beszel-agent. Created after first booting the hub.
  "beszel-agent-env.age".publicKeys = [ crussell ];

  # ── Hermes Agent (bee) ────────────────────────────────────────
  # Env file consumed by the hermes podman quadlet on bee. Holds
  # OPENROUTER_API_KEY, TELEGRAM_BOT_TOKEN + ALLOWED_USERS, API_SERVER_KEY,
  # and dashboard basic-auth credentials.
  "hermes-env.age".publicKeys = [ crussell ];
}

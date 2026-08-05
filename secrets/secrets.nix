let
  # Age public key for crussell (private key at ~/.config/age/key.txt)
  crussell = "age1uhmefj4e0jhf4nza9efsdz9qa8fq08sf04c3jh268cf3uhmlypfqh60u2v";
in
{
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

  # ── Gloo AI proxy credentials ─────────────────────────────────
  "gloo-credentials.age".publicKeys = [ crussell ];

  # ── Beszel monitoring ──────────────────────────────────────────
  # Env file (KEY=<hub public key>, TOKEN=<universal token>) shared by
  # every beszel-agent. Created after first booting the hub.
  "beszel-agent-env.age".publicKeys = [ crussell ];

  # ── Buzz self-hosted relay (podman pod on bee) ────────────────
  # One env file for all containers in the buzz-relay pod: relay identity,
  # owner pubkey, HMAC secret, and inlined PG/Redis/MinIO connection strings.
  # See hosts/bee/buzz-relay.nix.
  "buzz-relay-env.age".publicKeys = [ crussell ];

  # ── Buzz agent harness (buzz-acp on bee) ──────────────────────
  # Per-agent env file: BUZZ_PRIVATE_KEY=<nsec-or-hex> for each agent
  # identity that runs server-side. Mint a fresh keypair per agent
  # (e.g. `buzz-admin generate-key`) — do NOT reuse laptop agents.
  "buzz-agent-bumble-env.age".publicKeys = [ crussell ];
  "buzz-agent-oracle-env.age".publicKeys = [ crussell ];

  # ── Hermes Agent gateway on bee (replaces buzz-acp) ────────────
  # Combined env: BUZZ_PRIVATE_KEY (Bee's identity) + OPENAI_API_KEY
  # (Z.AI key remapped for Hermes' OpenAI-compatible provider).
  "hermes-bee-env.age".publicKeys = [ crussell ];

  # ── Hermes Agent CLI/TUI/Desktop on thinkpad ───────────────────
  # OPENAI_API_KEY=<Z.AI coding key> so Hermes' OpenAI-compatible provider
  # resolver finds it. Same key value as zai-api-key.age (which exports it
  # under ZHIPU_API_KEY for opencode); remapped to OPENAI_API_KEY for Hermes.
  # Sourced into shells via dotfiles/.zshenv (age-decrypt on login) and into
  # the GUI desktop app via the ~/.local/bin/hermes-desktop wrapper.
  "hermes-thinkpad-env.age".publicKeys = [ crussell ];
}

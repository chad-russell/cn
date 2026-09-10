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

  # ── Discord webhook for bees-watch (see hosts/gateway/bees-watch.nix) ──
  # One line: DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/<id>/<token>
  # Webhook "bees-watch alerts" in the #infra channel (created by
  # hermes-glen 2026-09-09). Deliberate exception to the "no secrets on
  # the VPS" invariant — see the bees-watch.nix header for rationale.
  "discord-infra-webhook.age".publicKeys = [ crussell ];

  # ── Lemmy admin password (bees) ─────────────────────────────────
  # setup.admin_password for first-boot admin seeding (chad) via the
  # nixpkgs services.lemmy module. See hosts/bees/lemmy.nix.
  "lemmy-admin-password.age".publicKeys = [ crussell ];

  # ── Beszel monitoring ──────────────────────────────────────────
  # Env file (KEY=<hub public key>, TOKEN=<universal token>) shared by
  # every beszel-agent. Created after first booting the hub.
  "beszel-agent-env.age".publicKeys = [ crussell ];

  # ── Kan (kan.bn) on bees — trello.crussell.io ────────────────────
  # POSTGRES_PASSWORD, POSTGRES_URL, BETTER_AUTH_SECRET, KAN_ADMIN_API_KEY.
  "kan-env.age".publicKeys = [ crussell ];

  # ── Proton Pass agent token for bee ("Glen" vault) ───────────────
  # PROTON_PASS_PERSONAL_ACCESS_TOKEN (hermes-bee agent, 6m expiry — renew via
  # pass-cli agent renew) + PROTON_PASS_ENCRYPTION_KEY (env key provider for
  # headless pass-cli). Deployed 0440 group=hermes so agent shells (user
  # crussell) can source it directly without sudo.
  "proton-pass-env.age".publicKeys = [ crussell ];

  # ── Forgejo Actions runner on bee ──────────────────────────────
  # TOKEN for registering the bee runner against git.crussell.io.
  # Generated on gateway: forgejo actions generate-runner-token.
  "forgejo-runner-token.age".publicKeys = [ crussell ];

  # ── Forgejo Actions runner on bees (nix-host label) ────────────
  # Separate registration token from bee's — the module's ExecStartPre
  # re-registers whenever the token hash changes, so a shared file would
  # make both runners churn. Same generator on gateway.
  "forgejo-runner-token-bees.age".publicKeys = [ crussell ];

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

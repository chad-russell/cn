let
  # Age public key for crussell (private key at ~/.config/age/key.txt)
  crussell = "age1uhmefj4e0jhf4nza9efsdz9qa8fq08sf04c3jh268cf3uhmlypfqh60u2v";
in {
  "aws-env.age".publicKeys = [ crussell ];
  # ── OpenRouter API key (opencode) ─────────────────────────────
  "openrouter-api-key.age".publicKeys = [ crussell ];

  # ── Hindsight agent-memory server on bee ───────────────────────
  # HINDSIGHT_API_LLM_API_KEY (openrouter-api-key value, renamed for
  # the container — deepseek-v4.1-flash per-token since 2026-09-22,
  # after the coding-plan experiment starved interactive quota) +
  # HINDSIGHT_CP_ACCESS_KEY (UI gate). Deployed 0400
  # owner=crussell so the rootless user quadlet can read it
  # (hosts/bee/hindsight.nix).
  "hindsight-env.age".publicKeys = [ crussell ];

  # ── 9router AI provider gateway on bee ────────────────────────
  # JWT_SECRET (dashboard cookie signing), INITIAL_PASSWORD (first
  # dashboard login only — upstream default is 123456),
  # API_KEY_SECRET + MACHINE_ID_SALT (upstream defaults are public
  # strings). All randomly generated at creation. owner=crussell so the
  # rootless user quadlet can read it (hosts/bee/ninerouter.nix).
  "ninerouter-env.age".publicKeys = [ crussell ];

  # ── 9router API key for dsh (bee) ─────────────────────────────
  # NINEROUTER_API_KEY — Bearer key minted in the 9router dashboard
  # (name "dsh"), consumed by dsh-web via EnvironmentFile in
  # modules/dsh.nix (provider "ninerouter" → 10.10.0.12:20128).
  # Separate file from ninerouter-env.age (the container's own secret)
  # per consumer — openrouter-api-key/hindsight-env precedent.
  "ninerouter-dsh-key.age".publicKeys = [ crussell ];

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

  # ── Forgejo API token (tea, git.crussell.io) ───────────────────
  # FORGEJO_TOKEN (single line) — scoped write:repository, write:issue,
  # read:issue, write:user, read:user. Exported to login shells by the
  # zshenv cache (modules/server-shell.nix) and to dsh-web via
  # EnvironmentFile (modules/dsh.nix).
  "forgejo-token.age".publicKeys = [ crussell ];

  # ── Hermes Agent gateway on bee (single brain: Glen, all lanes) ─
  # 2026-09-06 single-brain collapse: the gloo work profile/bot was
  # retired; the default gateway serves personal + work lanes with one
  # bot (hermes-glen). This env carries its token plus GLOO_API_KEY
  # (work provider). Historical name kept to avoid re-encrypting.
  "hermes-bee-env-glen.age".publicKeys = [ crussell ];

  # ── Central logging: OpenObserve (bees) + RustFS (nas) ──────────
  # openobserve-env: ZO_ROOT_USER_EMAIL / ZO_ROOT_USER_PASSWORD (UI
  # login AND OTLP basic auth for every Vector shipper — consumed on
  # all four NixOS hosts via modules/vector-log-shipper.nix and by the
  # bees quadlet in hosts/bees/openobserve.nix) plus
  # ZO_S3_ACCESS_KEY / ZO_S3_SECRET_KEY. The S3 values DUPLICATE
  # rustfs-env.age below — rotate both files together.
  # PASSWORD POLICY (boot-enforced, 2026-09-25 lesson): OpenObserve
  # rejects weak ZO_ROOT_USER_PASSWORD at startup (8-128 chars,
  # lower+upper+digit+special) — the failure surfaces as the misleading
  # panic "backend job init failed: channel closed". Generated values
  # must guarantee all four character classes.
  "openobserve-env.age".publicKeys = [ crussell ];

  # rustfs-env: RUSTFS_ACCESS_KEY / RUSTFS_SECRET_KEY for the shared
  # nas instance (hosts/nas/rustfs.nix). Values mirrored as ZO_S3_* in
  # openobserve-env.age.
  "rustfs-env.age".publicKeys = [ crussell ];

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

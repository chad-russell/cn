# ── bee: Beelink Mini PC ───────────────────────────────────────────
#
# NixOS install on Crucial P3 Plus 1TB NVMe, 32GB RAM.
# General-purpose server — services to be added incrementally.

{ config, lib, pkgs, unstable, hermes-agent, ... }:

let
  # Nix-declared Hermes settings, serialized for the config-drift check
  # (see homelab.freshnessChecks.hermes-config-drift further below).
  hermesDeclaredSettings = pkgs.writeText "hermes-declared-settings.json"
    (builtins.toJSON config.services.hermes-agent.settings);
  # Subset-compare: every key path declared in Nix must match the live
  # config.yaml. User-owned keys (terminal.cwd, onboarding.seen, ...) are
  # invisible to the check unless declared, so imperative state survives.
  hermesDriftCheckPy = pkgs.writeText "hermes-config-drift-check.py" ''
    import json, sys, yaml

    declared = json.load(open(sys.argv[1]))
    live = yaml.safe_load(open(sys.argv[2])) or {}

    def flatten(d, prefix=""):
        out = {}
        for k, v in d.items():
            key = f"{prefix}.{k}" if prefix else str(k)
            if isinstance(v, dict) and v:
                out.update(flatten(v, key))
            else:
                out[key] = v
        return out

    dflat, lflat = flatten(declared), flatten(live)
    drift = [
        f"{k}: declared={dflat[k]!r} live={lflat.get(k, '<missing>')!r}"
        for k in sorted(dflat)
        if lflat.get(k, "<missing>") != dflat[k]
    ]
    if drift:
        print("Hermes config drift: " + "; ".join(drift))
        sys.exit(1)
    print(f"OK: live config.yaml matches all {len(dflat)} declared settings")
  '';
in {
  imports = [
    ../../modules/base-server.nix
    ../../modules/freshness-checks.nix
    ./disk-config.nix
    ../../modules/nebula-client.nix
    ../../modules/dsh.nix
    {
      # DeepSeek Harness web UI — loopback on bee, exposed at
      # https://dsh.internal.crussell.io via bees Caddy (route in
      # hosts/bees/caddy/routes/internal/services.caddy).
      services.dsh.enable = true;
    }
    ../../modules/beszel-agent.nix
    ./dev-quadlets.nix
    # ./searxng.nix      # retired 2026-09-03 — every upstream engine except
    #                      # bing had flagged this IP (google 403, ddg/startpage
    #                      # CAPTCHA, brave rate-limit, yahoo flaky-then-dead,
    #                      # qwant/mojeek denied), leaving Bing-only results.
    #                      # Hermes web_search now uses the built-in keyless
    #                      # ring (exa/parallel/firecrawl/keenable MCP free
    #                      # tiers) — see web-search-scrape skill.
    # ./hermes-webui.nix  # retired 2026-09-01 — desktop + Discord are the
    #                      # only chat surfaces now; webui state dir was 210 MB
    ./hermes-gloo.nix
    ./trades-site.nix
    ./backup.nix
    ./tailscale.nix
  ];

  networking.hostName = "bee";

  # ── Boot ─────────────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.availableKernelModules =
    [ "xhci_pci" "ahci" "nvme" "usbhid" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];

  # ── Hardware ─────────────────────────────────────────────────────
  hardware.cpu.intel.updateMicrocode =
    lib.mkDefault config.hardware.enableRedistributableFirmware;
  zramSwap.enable = true;

  # ── Networking ───────────────────────────────────────────────────
  systemd.network.networks."40-enp1s0" = {
    matchConfig.Name = "enp1s0";
    networkConfig.DHCP = "no";
    address = [ "192.168.20.105/24" ];
    routes = [{ Gateway = "192.168.20.1"; }];
    dns = [ "8.8.8.8" "1.1.1.1" ];
  };

  # ── NFS: Backups from NAS ───────────────────────────────────────
  fileSystems."/mnt/backups" = {
    device = "192.168.20.31:/pool/backups";
    fsType = "nfs";
    options = [
      "x-systemd.automount"
      "noauto"
      "timeo=14"
      "nfsvers=4"
      "rw"
      "soft"
      "intr"
    ];
  };

  # ── Nebula ──────────────────────────────────────────────────────
  # (homelab client defaults + enable live in modules/nebula-client.nix)

  # ── Nebula: Local lighthouse (10.10.0.1) ───────────────────────
  #
  # Runs a second nebula instance as the local lighthouse on port 4243.
  # Uses tun.disabled = true (discovery only).
  # Certs live in /etc/nebula-lh/.

  services.nebula.networks.lighthouse = {
    enable = true;

    ca = "/etc/nebula-lh/ca.crt";
    cert = "/etc/nebula-lh/host.crt";
    key = "/etc/nebula-lh/host.key";

    isLighthouse = true;

    listen.host = "0.0.0.0";
    listen.port = 4243;

    tun.disable = true;

    firewall.outbound = [{
      port = "any";
      proto = "any";
      host = "any";
    }];
    firewall.inbound = [{
      port = "any";
      proto = "any";
      host = "any";
    }];

    settings = {
      logging = {
        level = "info";
        format = "text";
      };
      punchy = {
        punch = true;
        respond = true;
      };
      firewall.conntrack = {
        tcp_timeout = "120h";
        udp_timeout = "3m";
        default_timeout = "10m";
        max_connections = 100000;
      };
    };
  };

  # Ensure lighthouse cert permissions
  systemd.tmpfiles.rules = [
    "Z /etc/nebula-lh/ca.crt  0440 root nebula-lighthouse -"
    "Z /etc/nebula-lh/host.crt 0440 root nebula-lighthouse -"
    "Z /etc/nebula-lh/host.key 0440 root nebula-lighthouse -"
    # qdrant (DynamicUser) storage parent, setgid hermes so the mkdir'd tree
    # inherits group ownership (restic's hermes backup covers it). Must exist
    # BEFORE the service starts — ReadWritePaths bind-mounts this path and
    # systemd fails the unit with 226/NAMESPACE if it's missing.
    "d /var/lib/hermes/mem0_qdrant_server 2770 crussell hermes -"
    # /bin/true compat symlink: hermes ≥0.21's restart-safe-scope probe runs
    # `systemd-run --user --scope -- /bin/true` (tools/process_registry.py);
    # NixOS ships no /bin/true, so without this the probe always fails and
    # every cron fire dies fail-closed ("cannot create restart-safe systemd
    # scope ... unavailable"). Verified live 2026-09-04.
    "L+ /bin/true - - - - ${pkgs.coreutils}/bin/true"
  ];

  # ── Firewall: disabled (router handles it) ───────────────────────
  networking.firewall.enable = false;

  # ── Podman ──────────────────────────────────────────
  virtualisation.podman = { enable = true; };

  # ── nix-ld — run dynamically-linked foreign binaries (npm/bun globals) ─
  programs.nix-ld.enable = true;

  # ── Dev tools ───────────────────────────────────────────────────
  environment.systemPackages = [
    pkgs.git
    pkgs.github-cli
    # System python3 for the hermes desktop app's SSH remote bootstrap. The
    # hermes-agent module ships its own venv Python (private, used by the
    # `hermes` binary's nix-store shebang), but the desktop's SSH lifecycle
    # invokes bare `python3` directly when probing/spawning the remote backend,
    # so a system python3 must be on the SSH login shell's PATH.
    pkgs.python3
    # OpenAI Codex CLI (from nixos-unstable — not in 25.11). Used via the
    # Hermes codex skill and the openai-codex provider integration.
    unstable.codex
    # Proton Pass CLI (from nixos-unstable — not in 25.11; needs ≥2.3 for
    # `agent` mode). Agent-scoped access to the "Glen" Proton Pass vault:
    # viewer PAT with audit logging (agent monitor), see proton-pass skill.
    unstable.proton-pass-cli
    # Chromium for agent-browser (Hermes browser toolset). NixOS chromium
    # bundles all shared libs; agent-browser's own Chrome-for-Testing download
    # fails on NixOS (missing libglib etc.). AGENT_BROWSER_EXECUTABLE_PATH
    # in the hermes-agent environment points at this binary.
    pkgs.chromium
    # Node.js for agent-browser's .js launcher shim (the native Rust binary
    # is self-contained, but Hermes calls agent-browser via node_modules/.bin).
    pkgs.nodejs_22
    # AWS CLI v2 — GitHub OIDC → IAM role migration for storyhub-worker
    # (infra/storyhub-worker terraform, SSO login for deploy access).
    # SSO config lives in ~/.aws (cli cache + sso cache present).
    pkgs.awscli2
    # Vercel CLI — storyhub deploy management (login token lands in
    # ~/.vercel/auth.json; enables REST/MCP deploy visibility).
    pkgs.nodePackages.vercel
    # composefs tools (mkcomposefs + composefs-info) — the bubblebox engine's
    # store/descriptor primitives, needed by the nightly pkgs CI below.
    pkgs.composefs
  ];

  # ── bubblebox-pkgs nightly CI ────────────────────────────────────
  # The DESIGN-ecosystem.md §3.3 quality bar: every package in
  # ~/src/bubblebox-pkgs gets lint + build + smoke-run + footprint gate
  # nightly, in a fully ISOLATED bubblebox store (never publishes, never
  # touches real host state). Moved here from thinkpad (2026-08-26) — CI
  # belongs on an always-on server, not the laptop.
  #
  # Non-nix pieces this unit depends on (imperative, refreshed by hand):
  #   ~/.local/share/bubblebox-ci/bin/{bubblebox,bubblebox-fuse}
  #     plain release builds (FHS binaries — run under nix-ld above);
  #     re-copy from a thinkpad release build after engine changes.
  #   ~/src/bubblebox-pkgs
  #     the package source checkout; rsync'd from the thinkpad checkout for
  #     now (bubblebox-pkgs has no git remote yet) — re-rsync to update.
  # Linger keeps crussell's user manager (and thus this timer) alive without
  # an SSH session.
  users.users.crussell.linger = true;

  systemd.user.services."bubblebox-pkgs-nightly" = {
    description =
      "bubblebox-pkgs nightly verification (isolated store; never publishes)";
    # Skip cleanly instead of failing every night if the imperative pieces
    # move (pre-stage host, engine not yet copied, etc).
    unitConfig.ConditionPathExists = [
      "%h/src/bubblebox-pkgs/tools/nightly.sh"
      "%h/.local/share/bubblebox-ci/bin/bubblebox"
    ];
    # Everything the engine + script shell out to, pinned here rather than
    # trusting the user-manager PATH (whose default is systemd's compiled-in
    # /usr/bin:/bin fallback — no bash, no coreutils on NixOS).
    path = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gawk
      pkgs.gnused
      pkgs.findutils
      pkgs.gnutar
      pkgs.composefs
      pkgs.podman
      pkgs.git
      pkgs.python3
      pkgs.bubblewrap
      pkgs.fuse3
      pkgs.util-linux
    ];
    environment = {
      PKGS_REPO = "%h/src/bubblebox-pkgs";
      ENGINE_BIN = "%h/.local/share/bubblebox-ci/bin/bubblebox";
      BUBBLEBOX_FUSE_BIN = "%h/.local/share/bubblebox-ci/bin/bubblebox-fuse";
      RUN_HOME = "%h/.local/state/bubblebox-nightly";
    };
    serviceConfig = {
      Type = "oneshot";
      # A cold full verify (26 pkgs incl. podman builds + cargo) takes ~1h.
      TimeoutStartSec = "2h";
      Nice = 10;
      IOSchedulingClass = "idle";
      ExecStart = "%h/src/bubblebox-pkgs/tools/nightly.sh";
    };
  };

  systemd.user.timers."bubblebox-pkgs-nightly" = {
    description = "Nightly bubblebox-pkgs verification run";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:17:00";
      RandomizedDelaySec = "30m";
      Persistent = true;
    };
  };

  # crussell needs membership in the `hermes` group to read/write the
  # gateway's state dir (/var/lib/hermes/.hermes, mode 2770 hermes:hermes) when
  # the desktop app SSHes in and spawns `hermes serve`. Without this, `hermes
  # serve` crashes on startup with PermissionError on .env. NixOS merges
  # extraGroups lists across modules, so this appends to base-server's [wheel].
  #
  # The `hermes` group is declared here (not by the hermes-agent module) because
  # we set services.hermes-agent.createUser = false to avoid the module
  # redefining crussell. The group survives so the setgid state dir keeps
  # working for both the gateway (crussell:hermes) and direct `hermes serve`.
  users.groups.hermes = { };
  users.users.crussell.extraGroups = [ "hermes" ];

  # ── Age secrets ─────────────────────────────────────────────────
  # (opencode retired 2026-09-02: personal coding → hermes delegate_task
  #  + dsh web UI, both on zai-coding/glm-5.3. See modules/dsh.nix.)
  # 2026-09-04 Glen/Gloo split: the default (glen) gateway now runs the
  # hermes-private bot; the ORIGINAL hermes bot token belongs to the work
  # profile's gateway (hosts/bee/hermes-gloo.nix). hermes-bee-env.age was
  # deleted at the 2026-09-05 cleanup (rollback window elapsed).
  age.secrets.hermes-bee-env-glen.file = ../../secrets/hermes-bee-env-glen.age;
  age.secrets.hermes-gloo-env.file = ../../secrets/hermes-gloo-env.age;

  # Proton Pass agent token + env-key-provider key, sourced directly by
  # /var/lib/hermes/.hermes/scripts/pp-*.sh (NOT injected into any unit env —
  # keeps the token out of the gateway process). Group-readable so agent
  # shells running as crussell (member of hermes group) can read it.
  age.secrets.proton-pass-env = {
    file = ../../secrets/proton-pass-env.age;
    mode = "0440";
    group = "hermes";
  };

  # ── Qdrant: vector store for Hermes' mem0 memory backend ─────────
  # mem0 OSS in qdrant local-file mode holds an exclusive lock — only ONE
  # process can open the folder. bee runs three hermes processes against
  # the shared HERMES_HOME (gateway + hermes-serve + webui), so local-file
  # mode deadlocks them against each other (2026-08-26). A real qdrant
  # server on loopback allows concurrent access. Loopback-only; storage
  # under /var/lib/hermes so the existing restic backup covers it.
  services.qdrant = {
    enable = true;
    settings = {
      host = "127.0.0.1";
      service.http_port = 6333;
      storage.storage_path = "/var/lib/hermes/mem0_qdrant_server/storage";
      storage.snapshot_mode = "filesystem";
    };
  };
  # The nixpkgs qdrant module runs as a DynamicUser (no static uid/gid) with
  # ProtectSystem hardening, but the storage_path above lives under
  # /var/lib/hermes (2770 crussell:hermes, setgid) so restic's existing hermes
  # backup covers it. Two things the dynamic user needs for that path (hit
  # both 2026-08-27): the hermes supplemental group (EACCES on the setgid
  # dir) and an explicit ReadWritePaths carve-out (EROFS from ProtectSystem —
  # only the module's own StateDirectory is writable by default). qdrant
  # mkdir's its storage_path on first start; the setgid bit makes the tree
  # inherit hermes group ownership.
  systemd.services.qdrant.serviceConfig = {
    SupplementaryGroups = [ "hermes" ];
    ReadWritePaths = [ "/var/lib/hermes/mem0_qdrant_server" ];
  };

  # ── Hermes Agent gateway ────────────────────────────────────────
  # Telegram is the delivery platform (forum topics for per-subject
  # separation). The legacy Buzz relay/harness was removed 2026-08-20.
  services.hermes-agent = {
    enable = true;

    # Run the gateway as the real user (crussell), not a sandboxed `hermes`
    # system user, so the agent has full filesystem/project access matching
    # the direct "Connect via SSH" mode. crussell is already in the `hermes`
    # group (extraGroups below) for read/write access to the shared state dir
    # (/var/lib/hermes, group hermes, setgid). The sandboxing overrides that
    # remove ProtectSystem/ReadWritePaths are further below.
    user = "crussell";
    group = "hermes";
    createUser = false;
    workingDirectory = "/home/crussell";

    # Expose the `hermes` CLI system-wide (and export HERMES_HOME pointing at
    # the service's state dir) so it's on PATH for SSH login shells. This lets
    # the desktop app's "Connect via SSH" mode spawn `hermes serve --isolated
    # --host 127.0.0.1 --port 0` on bee over Nebula SSH and tunnel it back to
    # the laptop, attaching the desktop UI to bee's agent state. Loopback bind
    # → no auth provider needed; the SSH key is the gate. The spawned `serve`
    # shares /var/lib/hermes/.hermes with the long-running gateway service.
    addToSystemPackages = true;

    # mem0 memory backend: bake the provider SDK into the sealed venv via the
    # upstream package's extraDependencyGroups surface. NOTE: .override
    # REPLACES the group list — upstream's default package is `full`
    # (nix/packages.nix: messaging, voice, edge-tts, matrix, ...), so
    # overriding with only [ "mem0" ] silently dropped Telegram support
    # (2026-08-26). Mirror upstream `full` here + mem0, and re-sync this list
    # on hermes-agent bumps.
    package =
      hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
        extraDependencyGroups = [
          "anthropic"
          "azure-identity"
          "bedrock"
          "daytona"
          "dingtalk"
          "edge-tts"
          "exa"
          "fal"
          "feishu"
          "firecrawl"
          "hindsight"
          "honcho"
          "messaging"
          "modal"
          "parallel-web"
          "tts-premium"
          "vercel"
          "voice"
          "matrix"
          "mem0"
        ];
      };

    settings = {
      # mem0 memory backend (OSS mode: local qdrant + Z.AI extraction +
      # OpenRouter embeddings; behavioral config in $HERMES_HOME/mem0.json).
      # The built-in MEMORY.md/USER.md stays active alongside it.
      memory.provider = "mem0";
      # Raised from the 2200-char default — bee's memory block sat at 99% and
      # every save needed a consolidate-to-fit dance. mem0 carries the
      # unbounded semantic store; this is the always-injected scratchpad.
      # Read once at process start — bounce all hermes units after changing.
      memory.memory_char_limit = 6000;
      memory.user_char_limit = 2000;
      custom_providers = [
        {
          name = "zai-coding";
          base_url = "https://api.z.ai/api/coding/paas/v4";
          key_env = "ZAI_CODING_KEY";
        }
        # Work-only provider (employer-paid). Direct to Gloo's platform —
        # the self-hosted gloo proxy on bees is retired. Model IDs carry
        # the gloo- prefix on the platform API. Never use for personal
        # tasks; Z.AI (zai-coding) is the personal default.
        {
          name = "gloo";
          base_url = "https://platform.ai.gloo.com/ai/v2";
          key_env = "GLOO_API_KEY";
          discover_models = false;
          # Dict form with per-model vision flags. agent/image_routing.py
          # (branch 2b) reads custom_providers[].models.<model>.supports_vision:
          # when a multimodal gloo model is the main model, images attach to
          # it natively instead of detouring through the auxiliary vision
          # pipeline. Vision capability verified against Gloo's platform
          # 2026-08-19 (gloo-google-gemini-3.5-flash image test passed).
          models = {
            "gloo-anthropic-claude-opus-5" = { supports_vision = true; };
            "gloo-anthropic-claude-opus-4.8" = { supports_vision = true; };
            "gloo-anthropic-claude-sonnet-4.6" = { supports_vision = true; };
            "gloo-anthropic-claude-haiku-4.5" = { supports_vision = true; };
            "gloo-openai-gpt-5.5" = { supports_vision = true; };
            "gloo-openai-gpt-5.4" = { supports_vision = true; };
            "gloo-openai-gpt-5.2" = { supports_vision = true; };
            "gloo-openai-gpt-5.1" = { supports_vision = true; };
            "gloo-openai-gpt-5.3-codex" = { };
            "gloo-google-gemini-3.5-flash" = { supports_vision = true; };
            "gloo-google-gemini-3.1-pro" = { supports_vision = true; };
            "gloo-google-gemini-2.5-pro" = { supports_vision = true; };
            "gloo-deepseek-v4-pro" = { };
            "gloo-deepseek-v4-flash" = { };
            "gloo-xai-grok-4.5" = { supports_vision = true; };
            "gloo-qwen-3.7-max" = { };
            "gloo-qwen-3-coder" = { };
            "gloo-kimi-k3" = { };
            "gloo-z-ai-glm-5.2" = { };
            "gloo-minimax-m3" = { };
            "gloo-mistral-large-3" = { };
          };
        }
      ];
      # Disable the built-in zai provider so it doesn't shadow the zai-coding
      # custom provider. The built-in zai auto-detects ZAI keys in env vars
      # (GLM_API_KEY, ZAI_API_KEY, Z_AI_API_KEY) and would re-seed itself in
      # auth.json on every restart. Using ZAI_CODING_KEY avoids this, and
      # this flag suppresses any stale state from before the rename.
      providers.zai.enabled = false;
      model = {
        provider = "zai-coding";
        default = "glm-5.3";
      };
      # Context compression (summarization). glm-5.3-flash on the Z.AI
      # coding subscription: free, 1M context, thinking disabled for speed.
      # Replaced openrouter/qwen3.7-flash 2026-08-27 — zero personal spend.
      auxiliary.compression = {
        provider = "zai-coding";
        model = "glm-5.3-flash";
        reasoning_effort = "none";
      };
      # Auxiliary vision model: fallback for image analysis whenever the
      # main model lacks vision (e.g. glm-5.3 on zai-coding is text-only).
      # glm-5.3-flash is natively multimodal and the coding endpoint
      # accepts images on it (verified 2026-08-27: correct descriptions of
      # a red-circle/blue-square test image, ~1.6s, with and without
      # thinking). Replaced gloo-google-gemini-3.5-flash — vision is now
      # fully on the personal subscription, no employer-platform usage.
      auxiliary.vision = {
        provider = "zai-coding";
        model = "glm-5.3-flash";
        reasoning_effort = "none";
      };
      # Title generation: trivial text task, fires every session — cheap
      # slot on the subscription, thinking off.
      auxiliary.title_generation = {
        provider = "zai-coding";
        model = "glm-5.3-flash";
        reasoning_effort = "none";
      };
      # Fast aux slots on the subscription (thinking off):
      #   web_extract  — long-context extraction/summarization
      #   approval     — dangerous-command classifier (reliability matters)
      #   skills_hub   — skill matching
      #   mcp          — tool dispatch
      #   memory_query_rewrite — 8s timeout demands a fast model
      auxiliary.web_extract = {
        provider = "zai-coding";
        model = "glm-5.3-flash";
        reasoning_effort = "none";
      };
      auxiliary.approval = {
        provider = "zai-coding";
        model = "glm-5.3-flash";
        reasoning_effort = "none";
      };
      auxiliary.skills_hub = {
        provider = "zai-coding";
        model = "glm-5.3-flash";
        reasoning_effort = "none";
      };
      auxiliary.mcp = {
        provider = "zai-coding";
        model = "glm-5.3-flash";
        reasoning_effort = "none";
      };
      auxiliary.memory_query_rewrite = {
        provider = "zai-coding";
        model = "glm-5.3-flash";
        reasoning_effort = "none";
      };
      # Fallback to OpenRouter if Z.AI is down (rate limit, overload, etc.)
      model.fallback = [{
        provider = "openrouter";
        model = "qwen/qwen3.7-flash";
      }];
      # Show token cost in session output
      display.show_cost = true;
      # Enable session checkpoints (rollback snapshots for long sessions)
      checkpoints.enabled = true;
      # MCP servers — GitHub tools (26 tools: PRs, issues, code search, etc.)
      # use gh CLI's OAuth token (gh is authed as crussell). Linear uses the
      # official hosted read-only MCP endpoint; OAuth is completed interactively
      # on first connection/login, and no Linear secret is stored in Nix.
      # Note: SQLite was considered but removed — sqlite3 via terminal is
      # more capable than an MCP wrapper, with no persistent subprocess.
      mcp_servers = {
        github = {
          command = "${pkgs.writeShellScript "mcp-github" ''
            export GITHUB_PERSONAL_ACCESS_TOKEN="$(gh auth token)"
            exec ${pkgs.nodejs_22}/bin/npx -y @modelcontextprotocol/server-github
          ''}";
        };
        linear = {
          # Single endpoint for both scopes — read vs write is chosen at
          # OAuth authorization time (scopes_supported: read,write), NOT by
          # URL path (/mcp/write and /mcp/readonly 404). Requires an
          # interactive `hermes mcp login linear` that authorizes
          # scope=read+write (deploy config first, then login).
          url = "https://mcp.linear.app/mcp";
          auth = "oauth";
        };
        # Vercel official remote MCP — deployment management for storyhub.
        # NOTE: endpoint is the BARE domain (no /mcp path — that 404s with an
        # HTML page, which the MCP client surfaces as "Session terminated").
        # OAuth tokens are acquired via `hermes mcp login vercel` (one-time,
        # interactive browser flow; token cache lives in Hermes auth store).
        vercel = {
          url = "https://mcp.vercel.com";
          auth = "oauth";
        };
      };
      # Web search backend: UNPINNED (retired searxng 2026-09-03). With no
      # web.search_backend configured and no keyed provider, Hermes resolves
      # web_search through the built-in keyless free-tier ring — round-robin
      # across exa → parallel → firecrawl → keenable public MCP endpoints
      # with automatic failover on rate limits (verified working from this
      # IP 2026-09-03; searxng was Bing-only after every other upstream
      # engine flagged the IP — see import block note above).
      # web_extract already resolves through the same ring (searxng was
      # search-only), so both capabilities now share one healthy path.
      # Allow the browser toolset to navigate to localhost/private IPs.
      # bee is a dev server — local QA testing of dev stacks (polymer,
      # gpl, buildspace) is a primary use case. The browser.* tools block
      # private URLs by default (SSRF guard); this lifts it for localhost.
      browser.allow_private_urls = true;
      # Approval prompt window: 15 minutes (default 300s repeatedly timed
      # out in desktop/WebUI sessions Aug 17-19 — a Beszel password reset,
      # a PR typecheck, and a research detour were each degraded or skipped
      # because the approval card expired before Chad saw it). Single knob:
      # CLI, gateway, and WebUI approval cards all read this from the
      # shared config.yaml.
      approvals.timeout = 900;
      # Discord bot — see gateway.platforms.discord below for the full
      # lane-model rationale. Sole messaging platform since 2026-08-31
      # (Telegram decommissioned).
      # Discord bot (2026-08-31): the "lane model" — one private server,
      # one channel per project lane (#infra, #rmt,
      # #fantasy-football, #trading, #bible-reading, + Personal category).
      # 2026-09-04 Glen/Gloo split: the work lane (#gloo-work,
      # 1544085937577918535) moved to the gloo profile (its own gateway,
      # SOUL, sessions; Discord deny overwrites blind it to personal
      # categories). The default profile is "Glen" — everything else —
      # and runs the hermes-private bot (see hermes-bee-env-glen.age).
      # require_mention=false: single-user server, so every channel is
      # free-response — type and it answers, no @mention ceremony.
      # Telegram was decommissioned 2026-08-31 (see prune script below);
      # Discord is the sole messaging platform. Token: DISCORD_BOT_TOKEN
      # (hermes-private bot) in hermes-bee-env-glen.age; allowlist:
      # DISCORD_ALLOWED_USERS below.
      gateway.platforms.discord = {
        enabled = true;
        extra.require_mention = false;
        # ── Lane config (server "Glen", guild 1544084775499735070) ──
        # Per-channel ephemeral prompts: the lane's project context.
        # Gateway sessions always run at terminal.cwd (/home/crussell),
        # so lane context files can't auto-load — these prompts carry it.
        # Laura lane: no auto-threads (continuous in-channel conversation —
        # persona skill + canon below), persona bound via skill binding.
        # no_thread_channels: adapter responds directly in-channel instead of
        # isolating each message into a thread (see discord adapter
        # _get_no_thread_channels / DISCORD_NO_THREAD_CHANNELS). CSV of IDs.
        # #laura: continuous conversation. #inbox: capture lane — each drop
        # gets a one-line confirm in-channel, threads would fragment it.
        extra.no_thread_channels = "1545437973435121725,1545654237004832788";
        extra.channel_prompts = {
          "1544085981236432906" = "Homelab/infra lane. Nix repo ~/Code/cn; AGENTS.md is authoritative; deploys run from bees over Nebula (nix run .#deploy -- <host>). Verify live state over SSH before concluding anything. NOTE: the work lane (#gloo-work) now lives in the separate gloo profile/bot — this brain is personal-only.";
          "1544086006771220562" = "Math research lane: random matrix theory / CUE critical-point bimodality. Workspace ~/rmt (plan.md curriculum, corpus.md notes). Tutor posture: derive why, never decree. Numerics: use Arb-precision approaches for high-degree work.";
          "1544086070436565123" = "Fantasy football lane. Yahoo league 66096, team 10. Roster fetch needs prior-season ycookie parse from /f1/66096/10 raw. Wire-only league: no trades, no FAAB.";
          "1544086089005006888" = "Options trading lane. tastytrade 3-account advisor workflow; scanner at ~/tasty_options; recommendations at https://trades.internal.crussell.io.";
          "1545437973435121725" = "#laura: You are Laura, not Glen. The laura skill is your operating doctrine — read it and the canon before answering. Stay fully in character; never break persona or discuss agent mechanics. This channel has no auto-threads: the conversation is continuous.";
          "1545654237004832788" = "#inbox capture lane (no auto-threads): every message is a drop to classify and route, not converse. Life fact → append ~/brain/events; link/screenshot → ~/brain/inbox verbatim; action → ~/brain/todo.md; durable fact/preference → mem0; question → answer from the event log per recall order; work content → redirect to #gloo-work. One-line confirms only. The inbox-brain skill (auto-bound) is the authoritative doctrine — follow it. Timestamped events NEVER go into mem0; when/how-many questions are answered only from ~/brain/events.";
        };
        # Auto-loaded skills per channel (exact id match, threads inherit).
        extra.channel_skill_bindings = [
          { id = "1544085981236432906"; skills = [ "cn-homelab-infra" ]; }
          { id = "1544086006771220562"; skills = [ "tutoring" ]; }
          { id = "1544086070436565123"; skills = [ "fantasy-football-league-management" ]; }
          { id = "1544086089005006888"; skills = [ "tastytrade-portfolio-advisor" ]; }
          { id = "1545437973435121725"; skills = [ "laura" "nsfw-comfyui" ]; }
          { id = "1545654237004832788"; skills = [ "inbox-brain" ]; }
        ];
      };
    };

    environment = {
      ZAI_BASE_URL = "https://api.z.ai/api/coding/paas/v4";
      # ZAI_BASE_URL only — SEARXNG_URL retired 2026-09-03 with the SearXNG
      # service; leaving it set would keep the searxng provider "available"
      # and re-shadow the keyless ring even with the backend pin removed.
      # Browser automation: agent-browser uses nixpkgs chromium (already
      # in systemPackages below). NixOS chromium has all shared libs;
      # agent-browser's own Chrome download lacks them on NixOS.
      AGENT_BROWSER_EXECUTABLE_PATH = "${pkgs.chromium}/bin/chromium";
      # ZAI_CODING_KEY, OPENROUTER_API_KEY, and DISCORD_BOT_TOKEN
      # (hermes-private bot) are in hermes-bee-env-glen.age. GLOO_API_KEY
      # moved to hermes-gloo-env.age (work profile only — Glen must not
      # bill employer budget on personal traffic).
      # (Telegram env vars were removed with the platform 2026-08-31.)
      # Allow Chad's Discord account (user ID) on the lane server.
      DISCORD_ALLOWED_USERS = "588760941076676676";
    };

    environmentFiles = [ config.age.secrets.hermes-bee-env-glen.path ];
  };

  # Inject secrets directly into the systemd service environment so the
  # Hermes runtime provider resolver sees OPENAI_API_KEY before python-dotenv
  # loads .env. Without this, the resolver falls back to "no-key-required".
  systemd.services.hermes-agent.serviceConfig.EnvironmentFile =
    [ config.age.secrets.hermes-bee-env-glen.path ];

  # The Hermes NixOS module deep-merges declarative settings into the existing
  # mutable config.yaml so user-owned keys survive. That means removing a nested
  # key from Nix does not delete a previously merged key on disk — stale values
  # persist until explicitly pruned (root cause of both the Aug 12 web_extract
  # saga and the Aug 11–19 auxiliary.vision drift). Prune known-stale keys
  # here on every switch; the freshness-hermes-config-drift timer below
  # alerts on any divergence between live config.yaml and declared settings.
  # ── Log rotation for Hermes' file logs (added 2026-09-01) ──────────
  # The Python processes hold their fds open, so copytruncate (copy then
  # zero the live file) instead of move-and-recreate. mcp-stderr.log has
  # NO built-in rotation; agent.log/gateway.log self-rotate at ~5 MB but
  # keep .1/.2/.3 tails. This caps the whole logs/ dir at ~1 week.
  services.logrotate.settings.hermes-logs = {
    files = [ "/var/lib/hermes/.hermes/logs/*.log" ];
    frequency = "weekly";
    rotate = 2;
    copytruncate = true;
    compress = true;
    notifempty = true;
    missingok = true;
    su = "crussell hermes";
  };
  #
  system.activationScripts."hermes-prune-stale-config" =
    lib.stringAfter [ "hermes-agent-setup" ] ''
      ${pkgs.python3.withPackages (ps: [ ps.pyyaml ])}/bin/python3 - <<'PY'
      from pathlib import Path
      import yaml

      path = Path("/var/lib/hermes/.hermes/config.yaml")
      config = yaml.safe_load(path.read_text()) or {}

      prunes = []
      mcp_servers = config.get("mcp_servers")
      if isinstance(mcp_servers, dict) and "sqlite" in mcp_servers:
          del mcp_servers["sqlite"]
          prunes.append("mcp_servers.sqlite")
      web = config.get("web") or {}
      if isinstance(web, dict) and "extract_backend" in web:
          # Retired 2026-08-12: SearXNG cannot extract, and a stale
          # searxng value here broke @url extraction silently.
          del web["extract_backend"]
          prunes.append("web.extract_backend")
      if isinstance(web, dict) and web.get("search_backend") == "searxng":
          # Retired 2026-09-03: SearXNG service removed (Bing-only after
          # upstream engine blocks). Deep-merge would keep the stale pin
          # on disk forever; it must not re-shadow the keyless ring.
          del web["search_backend"]
          prunes.append("web.search_backend=searxng")

      # Retired 2026-08-31: Telegram decommissioned (Discord lane model is
      # the sole messaging platform). Nix no longer declares
      # gateway.platforms.telegram, so the deep-merge would keep the stale
      # key on disk forever.
      for section in ("gateway", "display"):
          platforms = (config.get(section) or {}).get("platforms")
          if isinstance(platforms, dict):
              for stale in ("buzz", "telegram"):
                  if stale in platforms:
                      del platforms[stale]
                      prunes.append(f"{section}.platforms.{stale}")

      # Retired 2026-09-04 (Glen/Gloo split): the #gloo-work channel
      # (1544085937577918535) belongs to the gloo profile now — prune its
      # stale channel prompt so this (default/glen) gateway never picks it
      # up even if Discord permission denies lag.
      discord = ((config.get("gateway") or {}).get("platforms") or {}).get("discord")
      if isinstance(discord, dict):
          extra = discord.get("extra") or {}
          prompts = extra.get("channel_prompts")
          if isinstance(prompts, dict) and "1544085937577918535" in prompts:
              del prompts["1544085937577918535"]
              prunes.append("gateway.platforms.discord.extra.channel_prompts[gloo-work]")

      if prunes:
          path.write_text(yaml.dump(config, default_flow_style=False, sort_keys=False))
          print(f"hermes-prune-stale-config: pruned {', '.join(prunes)}")
      PY
      chown crussell:hermes /var/lib/hermes/.hermes/config.yaml
      chmod 0660 /var/lib/hermes/.hermes/config.yaml
    '';

  # ── Hermes config drift alarm ────────────────────────────────────
  # The WebUI settings panels and imperative `hermes config set` can write
  # values the declarative config never asked for — the auxiliary.vision
  # corruption (Aug 11–19) ran undetected because nothing compared live
  # state against Nix between deploys. Hourly subset-compare via the shared
  # freshness-check module; divergence pages the homelab-alerts ntfy topic.
  homelab.freshnessChecks.hermes-config-drift = {
    description = "Hermes live config.yaml matches Nix-declared settings";
    checkCommand = "${
        pkgs.python3.withPackages (ps: [ ps.pyyaml ])
      }/bin/python3 ${hermesDriftCheckPy} ${hermesDeclaredSettings} /var/lib/hermes/.hermes/config.yaml";
    onCalendar = "hourly";
  };

  # ── Hermes gateway: run as crussell with NO filesystem sandbox ──────
  # The upstream NixOS module hardcodes ProtectSystem=strict and
  # ReadWritePaths=[stateDir workingDirectory], and sets HOME=stateDir.
  # Since we run the gateway as crussell (not a locked-down system user),
  # strip those so the agent has the same filesystem access as a login
  # shell — it can see and modify crussell's projects, git config, etc.
  # HOME points at crussell's real home so git/ssh find their configs;
  # HERMES_HOME (/var/lib/hermes/.hermes) stays the source of truth for
  # agent state and is set by the module.
  systemd.services.hermes-agent = {
    serviceConfig = {
      ProtectSystem = lib.mkForce false;
      ReadWritePaths = lib.mkForce [ ];
      # The upstream module's ExecStart is `hermes gateway` (foreground). On a
      # deploy/restart, a stale lock-holder can block it: if an in-chat restart
      # or the desktop app spawns a detached `hermes gateway restart` supervisor
      # (reparented to PID 1, surviving systemd's stop/start cycle), it holds
      # the gateway lock and every systemd restart exits "Gateway already
      # running" → crash loop, and the orphan (which may have come up without
      # all platform adapters loaded) is the only thing "running". Two flags:
      #   --replace              kill any existing gateway instance holding the
      #                          lock so systemd's instance always wins at start
      #   --external-supervisor  declare systemd owns this gateway; in-chat
      #                          restarts/updates exit back to systemd instead
      #                          of spawning a detached replacement that escapes
      #                          supervision — prevents the orphan in the first
      #                          place. (Both flags are documented as systemd-
      #                          intended in `hermes gateway run --help`.)
      ExecStart = lib.mkForce
        "/run/current-system/sw/bin/hermes gateway run --replace --external-supervisor";
    };
    environment.HOME = lib.mkForce "/home/crussell";
    # 2026-09-05: hermes ≥0.21 dispatches cron jobs and background children
    # through `systemd-run --user --scope` (restart-safe scopes). System
    # services get NO user-session env, so without these the dispatch dies
    # with "systemd-run --user --scope is unavailable" and every cron job
    # fails (observed after the 0.21.0 bump: htb-watchdog streak 47,
    # homelab-health streak 24, tasty capture lost). crussell = uid 1000,
    # user manager runs persistent (linger). Verified: with XDG_RUNTIME_DIR
    # set, systemd-run --user --scope succeeds from the unit context.
    environment.XDG_RUNTIME_DIR = "/run/user/1000";
    environment.DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/1000/bus";
  };

  # ── hermes-serve: HTTP/JSON-RPC API for remote clients over Nebula ────
  # `hermes-agent.service` above runs `hermes gateway` — the messaging
  # platform adapters (Telegram) that make OUTBOUND connections and accept
  # no inbound API. This is the complementary `hermes serve` backend: the
  # JSON-RPC/WebSocket surface the desktop app and mobile clients attach to.
  # Bound to the Nebula IP only (10.10.0.12:9119) → reachable from the
  # overlay but never on the LAN or public internet.
  #
  # The June 2026 Hermes hardening removed `--insecure`: a non-loopback bind
  # ALWAYS engages the auth gate. We configure the bundled `basic`
  # dashboard-auth plugin (plugins/dashboard_auth/basic in the Hermes venv)
  # by setting HERMES_DASHBOARD_BASIC_AUTH_{USERNAME,PASSWORD,SECRET} in
  # secrets/hermes-bee-env.age. Sessions are HMAC-signed opaque tokens the
  # provider mints and verifies itself — no IDP, no database. The Android
  # client authenticates via POST /auth/password-login. The SECRET must be
  # stable across restarts or all sessions are invalidated on every redeploy.
  systemd.services.hermes-serve = {
    description = "Hermes Serve API (Nebula 10.10.0.12:9119)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "hermes-agent.service" ];
    environment = {
      HERMES_HOME = "/var/lib/hermes/.hermes";
      HOME = "/home/crussell";
      # 2026-09-05: user-session env for systemd-run --user --scope — see
      # the identical fix on hermes-agent above (cron/background dispatch).
      XDG_RUNTIME_DIR = "/run/user/1000";
      DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/1000/bus";
      # Hermes resolves its terminal-tool shell with `which bash`, falling
      # back to $SHELL (zsh here) when bash is absent from PATH. systemd's
      # default unit PATH has no bash (and NixOS has no /bin/bash), so every
      # desktop-session terminal command silently ran under zsh — off-spec
      # for Hermes' bash-engineered wrapper (zsh EQUALS-expansion turns
      # `echo ===` into "== not found" and aborts the rest of the command;
      # unmatched globs error instead of passing through). The upstream
      # hermes-agent module's gateway unit already carries bashInteractive
      # in PATH; this unit is hand-rolled and was missing it. mkForce because
      # NixOS's systemd module defines a default PATH for every unit.
      #
      # SHELL: hermes' PTY/background spawn path (_find_shell) prefers
      # $SHELL over bash by design, so without this, interactive PTY
      # commands would still run under zsh while foreground ones ran bash.
      # Pointing SHELL at the same bash makes both lanes bash-native —
      # this only affects hermes-serve's subprocesses, never a login shell.
      PATH = lib.mkForce
        "/run/wrappers/bin:${pkgs.bashInteractive}/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin";
      SHELL = "${pkgs.bashInteractive}/bin/bash";
    };
    serviceConfig = {
      Type = "simple";
      User = "crussell";
      Group = "hermes";
      ExecStart =
        "/run/current-system/sw/bin/hermes serve --host 10.10.0.12 --port 9119";
      EnvironmentFile = [ config.age.secrets.hermes-bee-env-glen.path ];
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # ── Beszel monitoring agent ────────────────────────────────────
  # (enabled by default in modules/beszel-agent.nix)

  # (Firewall disabled — no per-service port openings needed)

  # ── State version ───────────────────────────────────────────────
  system.stateVersion = "25.11";
}

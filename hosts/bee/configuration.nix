# ── bee: Beelink Mini PC ───────────────────────────────────────────
#
# NixOS install on Crucial P3 Plus 1TB NVMe, 32GB RAM.
# General-purpose server — services to be added incrementally.

{ config, lib, pkgs, unstable, hermes-agent, ... }:

{
  imports = [
    ../../modules/base-server.nix
    ../../modules/freshness-checks.nix
    ./disk-config.nix
    ../../modules/nebula-client.nix
    ../../modules/dsh.nix
    # filebrowser — nix-managed rootless quadlet (10.10.0.12:8093, D-017;
    # replaces the manual container 2026-09-19). Buzz stack removed same
    # day (D-014): buzz.nix, glen-buzz.nix, buzz-acp.nix deleted.
    ./filebrowser.nix
    # Static artifact host (artifacts.internal.crussell.io) — dsh skills
    # `artifacts` + `design` publish into ~/artifacts; this serves them
    ./artifacts.nix
    # Hindsight agent-memory server (hindsight.internal.crussell.io) —
    # API+MCP :8888, UI :9999, rootless quadlet; coding agents connect here.
    ./hindsight.nix
    # sweatshop software factory (http://bee:3300) — rootless quadlet serving
    # a production build of ~/sweatshop; deploys via its scripts/deploy.sh.
    ./sweatshop.nix
    # Nightly podman auto-update for rootless quadlets that set
    # AutoUpdate=registry (hindsight, filebrowser)
    ./podman-auto-update.nix
    {
      # DeepSeek Harness web UI — loopback on bee, exposed at
      # https://dsh.internal.crussell.io via bees Caddy (route in
      # hosts/bees/caddy/routes/internal/services.caddy).
      services.dsh.enable = true;
    }
    ../../modules/beszel-agent.nix
    # Journald → OpenObserve shipper (central logs on bees)
    ../../modules/vector-log-shipper.nix
    # ./searxng.nix      # retired 2026-09-03 — every upstream engine except
    #                      # bing had flagged this IP (google 403, ddg/startpage
    #                      # CAPTCHA, brave rate-limit, yahoo flaky-then-dead,
    #                      # qwant/mojeek denied), leaving Bing-only results.
    #                      # Hermes web_search now uses the built-in keyless
    #                      # ring (exa/parallel/firecrawl/keenable MCP free
    #                      # tiers) — see web-search-scrape skill.
    # ./hermes-webui.nix  # retired 2026-09-01 — desktop + Discord are the
    #                      # only chat surfaces now; webui state dir was 210 MB
    # ./hermes-gloo.nix  # removed 2026-09-06 (single-brain collapse — work
    #                      # lane folded into the default glen gateway)
    # ./trades-site.nix  # removed 2026-10-23 — v1 ~/tasty_options stack
    #                      # superseded by tastyquant (./tastyquant.nix,
    #                      # trades.internal.crussell.io)
    ./tastyquant.nix
    # tansweat (https://tansweat.internal.crussell.io) — rootless quadlet
    # running the CI-built zot image; sweatshop's successor.
    ./tansweat.nix
    # comfylab (https://comfylab.internal.crussell.io) — mobile ComfyUI
    # front-end, rootless quadlet on 10.10.0.12:3350 (CI-built zot image).
    ./comfylab.nix
    # Rootless podman API on Nebula :8750 for tansweat sandboxes
    ../../modules/tansweat-sandbox-host.nix
    { homelab.tansweatSandboxHost.enable = true; }
    ./forgejo-runner.nix # Actions runner for git.crussell.io (Forgejo on gateway)
    ./backup.nix
    ./tailscale.nix
    ./wol-watch.nix
    # ── NFS mount from NAS (shared option policy in lib/nfs-mount.nix) ──
    # Restic backup target (see modules/restic-backup.nix)
    (import ../../lib/nfs-mount.nix {
      device = "192.168.20.31:/pool/backups";
      mountPoint = "/mnt/backups";
    })
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
    # HERMES_HOME state-dir parent. The hermes-agent module's activation
    # creates /var/lib/hermes at switch time, but if the state is ever wiped
    # between switches the gateway crash-loops ("Permission denied /
    # Required directory does not exist") until the next activation —
    # observed live at the 2026-11-06 fresh-start wipe. Declare it here so
    # tmpfiles guarantees it at boot/apply, same convention as the module:
    # 2770 + setgid, crussell:hermes (the three units share via the group).
    # NOTE: `hermes chat` from an interactive shell still fails with
    # unsafe_control_permissions — upstream's gateway discovery rejects the
    # group bits on HERMES_HOME itself (gateway_runtime_discovery.home_mode_
    # unsafe). Pre-existing upstream behavior, unrelated to this rule; the
    # delivery surfaces (Discord gateway, hermes-serve API) don't use that
    # path.
    "d /var/lib/hermes 2770 crussell hermes -"
    # /bin/true compat symlink: hermes ≥0.21's restart-safe-scope probe runs
    # `systemd-run --user --scope -- /bin/true` (tools/process_registry.py);
    # NixOS ships no /bin/true, so without this the probe always fails and
    # every cron fire dies fail-closed ("cannot create restart-safe systemd
    # scope ... unavailable"). Verified live 2026-09-04.
    "L+ /bin/true - - - - ${pkgs.coreutils}/bin/true"
  ];

  # ── Firewall: disabled (router handles it) ───────────────────────
  networking.firewall.enable = false;

  # ── Podman ──────────────────────────────────────────────────
  virtualisation.podman = { enable = true; };

  # IP forwarding for published container ports (netavark DNAT) — see the
  # matching comment in hosts/bees/configuration.nix (2026-09-05: fleet bump
  # left forwarding=0 and killed all cross-host access to published ports).
  boot.kernel.sysctl."net.ipv4.conf.all.forwarding" = true;

  # ── nix-ld — run dynamically-linked foreign binaries (npm/bun globals) ─
  programs.nix-ld.enable = true;

  # ── SSH client: drop systemd-ssh-proxy include ─────────────────────
  # nixpkgs defaults this on, emitting `Include <systemd store
  # path>/…/20-systemd-ssh-proxy.conf` into /etc/ssh/ssh_config. The
  # root-owned store file trips OpenSSH's include security check inside
  # user namespaces (root maps to nobody), so every sandboxed agent
  # shell's ssh fails with "Bad owner or permissions" (2026-09-23; DSH
  # agent shells pushed git only via `ssh -F /dev/null`). The fragment
  # only adds machine/*, unix/*, vsock/* ProxyCommand aliases for
  # machined-registered containers/VMs — nothing here uses those.
  programs.ssh.systemd-ssh-proxy.enable = false;

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
    # nixpkgs 26.05 removed nodePackages and never exposed `vercel` at the
    # top level — use `npx vercel` (nodejs_22 above provides npx) until a
    # nixpkgs package returns.
    # pkgs.nodePackages.vercel
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
  #     re-copy from a bee container build (~/Code/bubblebox
  #     target-bookworm/release/ — see the bubblebox wiki Build-and-Run)
  #     after engine changes.
  #   ~/src/bubblebox-pkgs
  #     git clone of chad/bubblebox-pkgs (origin on git.crussell.io);
  #     nightly.sh `git pull --ff-only` keeps it current — push commits
  #     before expecting the CI to see them.
  # NOTE: non-login PATHs lack /run/wrappers/bin (setuid fusermount3) —
  #   the engine resolves the wrapper itself since bubblebox 8d59009 and
  #   pkgs tools/nightly.sh prepends it; don't strip that hardening.
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
      # git pulls origin over ssh (ssh://git@git.crussell.io:2222); without ssh
      # on PATH the nightly's `git pull --ff-only` fails silently (stderr is
      # discarded) and the run verifies a stale checkout.
      pkgs.openssh
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
  # Single brain since 2026-09-06: the default glen gateway
  # (hermes-agent.service) runs the hermes-glen bot for BOTH personal and
  # work lanes (Gloo Discord category); the gloo work gateway unit is gone.
  # hermes-bee-env-glen.age carries the hermes-glen bot token + GLOO_API_KEY
  # (folded in from the retired hermes-gloo-env.age at the collapse).
  age.secrets.hermes-bee-env-glen.file = ../../secrets/hermes-bee-env-glen.age;

  # Proton Pass agent token + env-key-provider key, sourced directly by
  # /var/lib/hermes/.hermes/scripts/pp-*.sh (NOT injected into any unit env —
  # keeps the token out of the gateway process). Group-readable so agent
  # shells running as crussell (member of hermes group) can read it.
  age.secrets.proton-pass-env = {
    file = ../../secrets/proton-pass-env.age;
    mode = "0440";
    group = "hermes";
  };

  # ── Hermes Agent gateway ────────────────────────────────────────
  # Discord is the delivery platform (lane model — see the platform
  # block below). Legacy Buzz relay/harness removed 2026-08-20; Telegram
  # decommissioned 2026-08-31.
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

    # Sealed-venv provider extras via the upstream package's
    # extraDependencyGroups surface. NOTE: .override REPLACES the group list —
    # upstream's default package is `full` (nix/packages.nix: messaging,
    # voice, edge-tts, matrix, ...), so overriding with a short list silently
    # dropped Telegram support (2026-08-26). Mirror upstream `full` here and
    # re-sync this list on hermes-agent bumps. (mem0 was once appended for
    # the memory backend — retired 2026-11-06 with the fresh-start wipe.)
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
          # ("hindsight" dropped 2026-10-01: upstream removed the extra, and
          # the new strict resolver fails eval on unknown groups.
          # "honcho" AND "mem0" dropped 2026-10-15: memory providers left
          # core and became catalog plugins (hermes_cli/
          # memory_provider_migration.py _LEFT_CORE) — the agent auto-
          # installs mem0 into HERMES_HOME/plugins on startup / `hermes
          # update`.
          "messaging"
          "modal"
          "parallel-web"
          "tts-premium"
          "vercel"
          "voice"
          "matrix"
        ];
      };

    settings = {
      # Custom providers in the MODERN v12+ `providers:` DICT shape (keyed
      # by provider id), NOT the legacy `custom_providers:` list.
      #
      # WHY (2026-09-07 incident — "Provider authentication failed"):
      # Hermes 0.21.0 runs a v11→v12 config migration that converts a
      # `custom_providers` LIST into a `providers` DICT and pops the list
      # (config_migrations.py:_migrate_to_12). The NixOS module deep-merges
      # our declared settings into config.yaml on every switch
      # (hermes-agent nix/configMergeScript.nix). When Nix declared the
      # legacy LIST, the module's merge and Hermes' own migration fought:
      # a switch left `providers:` holding LIST content, which the runtime
      # reader (config_providers.providers_dict_to_custom_providers) rejects
      # because it requires a dict — so zai-coding AND gloo silently vanished
      # ("Unknown provider 'zai-coding'") and every request, including all
      # auxiliary slots, failed provider auth with the fallback also failing.
      # Declaring the dict form directly makes the NixOS merge and the Hermes
      # migration agree on ONE shape; verified idempotent under a full
      # v0→current migration pass, so it cannot regress on a future
      # switch/restart. Runtime still reads a list view via
      # get_compatible_custom_providers(). Modern entries use `api:` for the
      # base URL (not `base_url:`); an explicit `enabled = false` hides a
      # provider from the picker/resolver/doctor (is_provider_enabled).
      providers = {
        # Disable the built-in zai provider so it doesn't shadow the
        # zai-coding custom provider. The built-in zai auto-detects ZAI keys
        # in env vars (GLM_API_KEY, ZAI_API_KEY, Z_AI_API_KEY) and would
        # re-seed itself in auth.json on every restart. Using ZAI_CODING_KEY
        # avoids this, and this flag suppresses any stale state.
        zai.enabled = false;

        zai-coding = {
          api = "https://api.z.ai/api/coding/paas/v4";
          key_env = "ZAI_CODING_KEY";
        };

        # Work-only provider (employer-paid). Direct to Gloo's platform —
        # the self-hosted gloo proxy on bees is retired. Model IDs carry
        # the gloo- prefix on the platform API. Never use for personal
        # tasks; Z.AI (zai-coding) is the personal default.
        gloo = {
          api = "https://platform.ai.gloo.com/ai/v2";
          key_env = "GLOO_API_KEY";
          discover_models = false;
          # Per-model vision flags. agent/image_routing.py (branch 2b) reads
          # providers.<name>.models.<model>.supports_vision: when a
          # multimodal gloo model is the main model, images attach to it
          # natively instead of detouring through the auxiliary vision
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
            "gloo-z-ai-glm-5.3" = { };
            "gloo-z-ai-glm-5.3-flash" = { };
            "gloo-minimax-m3" = { };
            "gloo-mistral-large-3" = { };
          };
        };
      };
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
      # Fallback chain when the primary fails (rate limit, overload, auth,
      # connection). MUST be top-level `fallback_providers` — hermes reads
      # ONLY that key (hermes_cli/fallback_config.py::get_fallback_chain);
      # a nested model.fallback is silently ignored. Found 2026-09-08: the
      # previous `model.fallback` declaration was dead config and bee ran
      # with NO effective fallback. Pruned on switch (see activation script).
      # Hop 1: same Z.AI subscription (free, absorbs soft rate limits).
      # Hop 2: OpenAI Codex subscription (company-given, ChatGPT OAuth
      # credential in auth.json — verified `hermes auth status openai-codex`).
      # Genuinely cross-provider: covers a full Z.AI outage. gpt-5.5 (not
      # gpt-5.3-codex) because fallback must continue the full agent tool
      # loop, which wants the general model. Fires only on failure-class
      # errors; primary is restored automatically next turn.
      fallback_providers = [
        {
          provider = "zai-coding";
          model = "glm-5.3-flash";
        }
        {
          provider = "openai-codex";
          model = "gpt-5.5";
        }
      ];
      # Pull-based access to the Codex subscription: `/model gpt` in any
      # session (session-scoped; `--global` to persist) routes to GPT-5.5 on
      # the OAuth provider. Other catalog slugs (`gpt-5.6-sol`, `gpt-5.4`,
      # ...) resolve natively once the provider is active. User aliases
      # shadow builtins, so this pins `gpt` to the Codex OAuth path rather
      # than the API-key path we have no key for. Agentic coding stays on
      # the codex CLI (see the codex skill) — this alias is for pulling
      # extra reasoning into a normal session, not delegation.
      model_aliases.gpt = {
        provider = "openai-codex";
        model = "gpt-5.5";
      };
      # Show token cost in session output
      display.show_cost = true;
      # Enable session checkpoints (rollback snapshots for long sessions)
      checkpoints.enabled = true;
      # Retention (HML-4, 2026-09-07): pin upstream v0.21.0 defaults
      # declaratively. The gateway's startup sweep (idempotent via
      # checkpoints/.last_prune, >=24h apart) drops projects untouched
      # for 7d, GCs the shared git store, and
      # round-robin drops oldest commits until the store fits the size cap.
      # NOTE: the cap cannot go below one commit per LIVE project — the agent
      # checkpoints ~60 workdirs (skill dirs, Code/*, /tmp scratch), so
      # ~600MB is the expected steady state, not a leak. Orphans (PrivateTmp
      # /tmp dirs, retired gloo profile paths) are kept until the 7d stale
      # rule ages them out — the identity check refuses mount-namespace
      # mismatches by design; don't force-delete.
      checkpoints.auto_prune = true;
      checkpoints.retention_days = 7;
      checkpoints.max_total_size_mb = 500;
      checkpoints.max_snapshots = 20;
      checkpoints.min_interval_hours = 24;
      # MCP servers — GitHub tools (26 tools: PRs, issues, code search, etc.)
      # use gh CLI's OAuth token (gh is authed as crussell).
      # Note: SQLite was considered but removed — sqlite3 via terminal is
      # more capable than an MCP wrapper, with no persistent subprocess.
      # 2026-09-16: linear + vercel MCP servers REMOVED (hygiene audit).
      # Zero mcp__linear/mcp__vercel tool calls in agent.log history and
      # no OAuth tokens in auth.json (never completed `hermes mcp login`).
      # Work tooling lives in the gloo lane/codex CLI per the 09-06
      # single-brain doctrine; if Linear access is ever needed again,
      # re-add here + `hermes mcp login linear` in a PTY.
      mcp_servers = {
        github = {
          command = "${pkgs.writeShellScript "mcp-github" ''
            export GITHUB_PERSONAL_ACCESS_TOKEN="$(gh auth token)"
            exec ${pkgs.nodejs_22}/bin/npx -y @modelcontextprotocol/server-github
          ''}";
        };
        # Monarch Money (read-only), 2026-09-10 — replaces the manual CSV
        # export path. Third-party stdio MCP (robcerda/monarch-mcp-server,
        # clone at ~/Code/monarch-mcp-server on bee, uv-managed venv; the
        # console entry point has an absolute shebang so no PATH needed).
        # Auth: one-time interactive `uv run login_setup.py` (choice 1,
        # browser cookie) → session blob at ~/.monarch-mcp-server/token
        # (bee has no keyring backend — keyring.backends.fail — so the
        # library's file fallback applies: 0700 dir, 0600 file, atomic
        # writes; gateway runs as crussell with HOME=/home/crussell, so
        # the MCP child finds it). Re-auth when the session expires:
        #   1. Copy the `cookie:` request header from app.monarch.com
        #      DevTools → Network → any graphql request.
        #   2. ssh bee 'umask 077; mkdir -p ~/.config/monarch-mcp; cat >
        #      ~/.config/monarch-mcp/cookie.txt'  (paste, Ctrl-D) — direct
        #      terminal pastes truncate at ~1024 chars (MAX_CANON), which
        #      is why the file route is required.
        #   3. cd ~/Code/monarch-mcp-server &&
        #      SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
        #      uv run login_setup.py
        #      (choice 1; reads the file automatically, keeps the old
        #      session until the new one verifies. The SSL_CERT_FILE
        #      prefix is REQUIRED — same uv-python CA gap as the wrapper
        #      below; without it login fails with CERTIFICATE_VERIFY_FAILED,
        #      observed 2026-09-11).
        # MONARCH_MCP_READ_ONLY=1 makes the server never REGISTER its
        # mutating tools (create/update/delete transactions, bulk ops,
        # budget/rule/category edits, splits, tags, login/logout) —
        # stronger than approval gating: unregistered tools cannot be
        # invoked at all. If the repo is updated: `git pull && uv sync`,
        # then redeploy is NOT needed (command points at the live venv).
        monarch = {
          command = "${pkgs.writeShellScript "mcp-monarch" ''
            export MONARCH_MCP_READ_ONLY=1
            export HOME=/home/crussell
            # The venv python (uv cpython) hardcodes /etc/ssl/cert.pem as its
            # OpenSSL CA default, which does not exist on NixOS; without this
            # every api.monarch.com call dies with CERTIFICATE_VERIFY_FAILED
            # (observed 2026-09-11). Set explicitly so the wrapper works from
            # any parent env, not just the gateway's.
            export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
            exec /home/crussell/Code/monarch-mcp-server/.venv/bin/monarch-mcp-server
          ''}";
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
      # Protected agent-instruction files (AGENTS.md / CLAUDE.md / SOUL.md /
      # .cursorrules): upstream default is an always-ask approval gate that
      # fails closed for headless workers (their AGENTS.md edits block
      # until an approval times out). Chad opted out 2026-09-06: these repos
      # are his own, watched via code review, and the workers' whole job is
      # editing them. Gate OFF — agents may write instruction files directly.
      security.protected_instruction_files = false;
      browser.allow_private_urls = true;
      # Approval prompts OFF (Chad 2026-09-08): every prompt he's ever
      # gotten he blindly approved, and prompt timeouts degraded more work
      # than the gate ever caught — so skip the ask entirely. NOT naked
      # yolo: tools/approval.py runs an unconditional floor BEFORE the
      # mode=off bypass, which no setting can turn off — hardline
      # catastrophic commands (rm -rf /, fork bombs, dd to devices), the
      # sudo-stdin password guard, and any future approvals.deny rules
      # stay enforced. timeout stays as the fallback window if mode is
      # ever flipped back to smart/manual (single knob: CLI, gateway, and
      # desktop approval cards all read it from the shared config.yaml;
      # raised to 900s 2026-08-19 after 300s defaults kept expiring).
      approvals.mode = "off";
      approvals.timeout = 900;
      # Discord — minimal surface (2026-11-06 fresh-start trim): the bot
      # responds ONLY in #general (the allowlist gate — extra.allowed_channels
      # seeds DISCORD_ALLOWED_CHANNELS; DMs still work via the user allowlist)
      # plus DMs. The lane-per-channel model (#gloo-general, #infra, #rmt,
      # #fantasy-football, #trading, #inbox prompts/overrides/bindings) was
      # retired the same day — wrong abstraction to pre-wire; channels gain
      # doctrine when a real workflow emerges (IDs recoverable from git
      # history, this commit's parent). require_mention=false stays: in the
      # one allowed channel the bot free-responds, no @mention ceremony.
      gateway.platforms.discord = {
        enabled = true;
        extra.require_mention = false;
        # #general (guild "Glen") — the only responding channel.
        extra.allowed_channels = "1544084776363888723";
        # Home channel — fallback delivery target for cron deliveries
        # (daily-hermes-state-backup) and cross-platform messages.
        home_channel = {
          platform = "discord";
          chat_id = "1544084776363888723";
          name = "general";
        };
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
      # ZAI_CODING_KEY, OPENROUTER_API_KEY, DISCORD_BOT_TOKEN (hermes-glen
      # bot) and GLOO_API_KEY (work provider — folded in 2026-09-06 when the
      # gloo gateway was retired; the single brain serves work too) are in
      # hermes-bee-env-glen.age.
      # (Telegram env vars were removed with the platform 2026-08-31.)
      # Allow Chad's Discord account (user ID) on the lane server.
      DISCORD_ALLOWED_USERS = "588760941076676676";
    };

    environmentFiles = [ config.age.secrets.hermes-bee-env-glen.path ];
  };

  # Inject secrets directly into the systemd service environment so the
  # Hermes runtime provider resolver sees OPENAI_API_KEY before python-dotenv
  # loads .env. Without this, the resolver falls back to "no-key-required".
  #
  # 2026-09-07 rootless-podman fix (26.05 hop brought shadow 4.19): the setuid
  # newuidmap/newgidmap now reject target processes whose PRIMARY gid differs
  # from the passwd entry's pw_gid ("Target process is owned by a different
  # user"). The module's Group = "hermes" gave gateway children primary gid 990
  # while crussell's passwd gid is 100 (users) — so every rootless-podman
  # spawn from gateway children (agent terminal tools, cron scripts like the
  # tasty 9am brief's ./run) died at newuidmap with exit 125. The unit's
  # primary group MUST be the passwd group; hermes stays SUPPLEMENTARY so the
  # setgid /var/lib/hermes sharing (UMask 0007, group-writable state dirs,
  # tmpfiles 2770 user:hermes) is completely unchanged. mkForce because the
  # upstream module's commonServiceConfig also sets Group.
  systemd.services.hermes-agent.serviceConfig = {
    EnvironmentFile = [ config.age.secrets.hermes-bee-env-glen.path ];
    Group = lib.mkForce "users";
    SupplementaryGroups = [ "hermes" ];
  };

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

  # ── hermes-checkpoints-prune: daily checkpoint retention sweep ──────
  # The gateway's auto_prune sweep (checkpoints.auto_prune) runs at STARTUP
  # only (maybe_auto_prune_checkpoints is a startup hook, rate-limited 24h
  # via checkpoints/.last_prune). The gateway stays up for weeks between
  # deploys, so on a long-lived process nothing re-enforces retention — and
  # the in-checkpoint size cap cannot reclaim single-commit refs
  # (_drop_oldest_commit never drops below one commit per project), so the
  # only real reclaim path is this stale/orphan sweep. HML-4's "else a prune
  # cron" fallback: run the same prune the startup hook would run, daily.
  # Args are pinned to the declared knobs above — keep them in sync.
  systemd.services.hermes-checkpoints-prune = {
    description = "Hermes checkpoint store retention prune (HML-4)";
    environment = {
      HERMES_HOME = "/var/lib/hermes/.hermes";
      HOME = "/home/crussell";
    };
    serviceConfig = {
      Type = "oneshot";
      User = "crussell";
      Group = "hermes";
      # git gc over the shared pack — keep it off the foreground I/O path.
      Nice = 10;
      IOSchedulingClass = "idle";
      ExecStart = "/run/current-system/sw/bin/hermes checkpoints prune -f"
        + " --retention-days 7 --max-size-mb 500";
      # The prune runs git ref expire + gc --prune=now against the live
      # gateway's store. Git's own ref/pack locking serializes the two
      # writers (the startup sweep runs this same code with agents live),
      # but bound it so a stuck gc can't hold a deploy restart.
      TimeoutStartSec = "10m";
    };
  };

  systemd.timers.hermes-checkpoints-prune = {
    description = "Daily Hermes checkpoint retention prune (HML-4)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # 04:41 — after the 04:17 bubblebox window, before the 09:00 state
      # snapshot; deliberately staggered from both.
      OnCalendar = "*-*-* 04:41:00";
      RandomizedDelaySec = "10m";
      Persistent = true;
    };
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
      # 2026-09-07: primary group = passwd group (users), hermes supplementary
      # — same rootless-podman/newuidmap fix as hermes-agent above (shadow
      # 4.19 rejects targets whose primary gid ≠ pw_gid; serve children hit
      # it identically). Sharing via setgid dirs + supplementary group.
      Group = "users";
      SupplementaryGroups = [ "hermes" ];
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

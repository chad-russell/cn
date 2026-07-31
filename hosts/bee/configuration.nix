# ── bee: Beelink Mini PC ───────────────────────────────────────────
#
# NixOS install on Crucial P3 Plus 1TB NVMe, 32GB RAM.
# General-purpose server — services to be added incrementally.

{ config, lib, pkgs, unstable, ... }:

{
  imports = [
    ../../modules/base-server.nix
    ../../modules/freshness-checks.nix
    ./disk-config.nix
    ../../modules/nebula-client.nix
    ../../modules/opencode.nix
    ../../modules/buzz-harness.nix
    ../../modules/beszel-agent.nix
    ./backup.nix
    ./tailscale.nix
  ];

  networking.hostName = "bee";

  # ── Boot ─────────────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];

  # ── Hardware ─────────────────────────────────────────────────────
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
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
    options = [ "x-systemd.automount" "noauto" "timeo=14" "nfsvers=4" "rw" "soft" "intr" ];
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

    firewall.outbound = [{ port = "any"; proto = "any"; host = "any"; }];
    firewall.inbound  = [{ port = "any"; proto = "any"; host = "any"; }];

    settings = {
      logging = { level = "info"; format = "text"; };
      punchy = { punch = true; respond = true; };
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
  ];

  # ── Firewall: disabled (router handles it) ───────────────────────
  networking.firewall.enable = false;

  # ── Podman ──────────────────────────────────────────
  virtualisation.podman = {
    enable = true;
  };

  # ── nix-ld — run dynamically-linked foreign binaries (npm/bun globals) ─
  programs.nix-ld.enable = true;

  # ── Dev tools ───────────────────────────────────────────────────
  environment.systemPackages = [
    pkgs.git
    pkgs.github-cli
  ];

  # ── opencode AI coding agent ────────────────────────────────────
  # (enable + web defaults live in modules/opencode.nix)

  # ── Buzz agent harness (buzz-acp) ───────────────────────────────
  # One systemd service per agent identity. Agents answer @mentions from any
  # client (phone/laptop) while bee stays always-on. See PLANS note + the
  # buzz-harness module for option reference.
  #
  # Before this is live you must (see modules/buzz-harness.nix + PLANS):
  #   1. Fix secrets/zai-api-key.age to set ZHIPU_API_KEY (not ZAI_API_KEY).
  #   2. Mint a keypair per agent: `buzz-admin generate-key` after first build.
  #   3. Create secrets/buzz-agent-<name>-env.age = `BUZZ_PRIVATE_KEY=<nsec>`.
  #   4. Add each agent's pubkey to the relay + channels via the Buzz desktop app.
  services.buzz-harness = {
    enable = true;
    # relayUrl defaults to wss://crussell.communities.buzz.xyz (hosted).
    agents = {
      # Primary agent — native buzz-agent on Z.AI Coding Plan (glm-5.2).
      bumble = {
        privateKeySecret = "buzz-agent-bumble-env";
        provider = "openai";
        model = "glm-5.2";
        # The shared zai-api-key secret exposes ZHIPU_API_KEY; buzz-agent's
        # openai provider wants OPENAI_COMPAT_API_KEY, so remap it.
        apiKeyEnvFrom = "ZHIPU_API_KEY";
        extraEnv = {
          OPENAI_COMPAT_BASE_URL = "https://api.z.ai/api/coding/paas/v4";
          OPENAI_COMPAT_API = "chat"; # force Chat Completions (endpoint isn't *.openai.com)
          # NIP-OA owner-attestation: lets the agent inherit the owner's relay
          # membership on hosted relays where the user isn't a relay admin.
          # Extracted from the desktop app's managed-agents.json. Not a secret.
          BUZZ_AUTH_TAG = ''["auth","93984b5c44debc12757e0f5db1643c2808ee8b820b46ac704febb039de4c16a7","","a5b2da36a39eb7569f10e823ecb699cf0ccef495149cdca5144118f0d751efdc636d2f707b90c7a9ae6e92355453283433edf33678af21ca3c6aa481cb48d961"]'';
        };
        environmentFiles = [
          config.age.secrets.zai-api-key.path # provides ZHIPU_API_KEY (after the fix)
        ];
        # Dedicated test channel (just you + the bot): respond to any owner
        # message, no @mention needed. Drop this once the agent has a proper
        # @ handle (re-created in the app) for use in shared channels.
        extraOptions = [ "--no-mention-filter" ];
      };

      # Secondary agent — OpenRouter (swap models freely per agent).
      # oracle = {
      #   privateKeySecret = "buzz-agent-oracle-env";
      #   provider = "openrouter";
      #   model = "anthropic/claude-sonnet-4.5";
      #   environmentFiles = [
      #     config.age.secrets.openrouter-api-key.path # provides OPENROUTER_API_KEY
      #   ];
      # };
    };
  };

  # ── Beszel monitoring agent ────────────────────────────────────
  # (enabled by default in modules/beszel-agent.nix)

  # (Firewall disabled — no per-service port openings needed)

  # ── State version ───────────────────────────────────────────────
  system.stateVersion = "25.11";
}

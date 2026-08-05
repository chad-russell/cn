# ── bee: Beelink Mini PC ───────────────────────────────────────────
#
# NixOS install on Crucial P3 Plus 1TB NVMe, 32GB RAM.
# General-purpose server — services to be added incrementally.

{ config, lib, pkgs, unstable, buzz, ... }:

{
  imports = [
    ../../modules/base-server.nix
    ../../modules/freshness-checks.nix
    ./disk-config.nix
    ../../modules/nebula-client.nix
    ../../modules/opencode.nix
    ../../modules/buzz-harness.nix
    ./buzz-relay.nix
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
    # System python3 for the hermes desktop app's SSH remote bootstrap. The
    # hermes-agent module ships its own venv Python (private, used by the
    # `hermes` binary's nix-store shebang), but the desktop's SSH lifecycle
    # invokes bare `python3` directly when probing/spawning the remote backend,
    # so a system python3 must be on the SSH login shell's PATH.
    pkgs.python3
  ];

  # crussell needs membership in the `hermes` group to read/write the
  # gateway's state dir (/var/lib/hermes/.hermes, mode 2770 hermes:hermes) when
  # the desktop app SSHes in and spawns `hermes serve`. Without this, `hermes
  # serve` crashes on startup with PermissionError on .env. NixOS merges
  # extraGroups lists across modules, so this appends to base-server's [wheel].
  users.users.crussell.extraGroups = [ "hermes" ];

  # ── opencode AI coding agent ────────────────────────────────────
  # (enable + web defaults live in modules/opencode.nix)

  # ── Buzz agent harness (buzz-acp) ───────────────────────────────
  # Disabled — replaced by Hermes Agent gateway (see below). Kept as a
  # fallback: re-enable by setting enable = true and disabling hermes-agent.
  services.buzz-harness.enable = false;

  # ── Age secrets ─────────────────────────────────────────────────
  age.secrets.hermes-bee-env.file = ../../secrets/hermes-bee-env.age;

  # ── Hermes Agent gateway (replaces buzz-acp for Bee) ────────────
  # Runs Hermes' native Buzz platform adapter: connects directly to the
  # relay via NIP-42-authenticated WebSocket, detects @mentions by message
  # content (not just p-tags), and uses the `buzz` CLI for outbound.
  # This solves the desktop v0.5.4 autocomplete filter that prevented
  # @-mentioning Bee (external agents without managed-list membership).
  services.hermes-agent = {
    enable = true;

    # Expose the `hermes` CLI system-wide (and export HERMES_HOME pointing at
    # the service's state dir) so it's on PATH for SSH login shells. This lets
    # the desktop app's "Connect via SSH" mode spawn `hermes serve --isolated
    # --host 127.0.0.1 --port 0` on bee over Nebula SSH and tunnel it back to
    # the laptop, attaching the desktop UI to bee's agent state. Loopback bind
    # → no auth provider needed; the SSH key is the gate. The spawned `serve`
    # shares /var/lib/hermes/.hermes with the long-running gateway service.
    addToSystemPackages = true;

    settings = {
      custom_providers = [
        {
          name = "zai-coding";
          base_url = "https://api.z.ai/api/coding/paas/v4";
          key_env = "OPENAI_API_KEY";
        }
      ];
      model = {
        provider = "zai-coding";
        default = "glm-5.2";
      };
      display.platforms.buzz = {
        interim_assistant_messages = false;
        tool_progress = "off";
      };
      gateway.platforms.buzz = {
        enabled = true;
        extra = {
          relay_url = "https://buzz.crussell.io";
          require_mention = true;
          allow_all_users = true;
        };
      };
    };

    environment = {
      BUZZ_RELAY_URL = "https://buzz.crussell.io";
      BUZZ_ALLOW_ALL_USERS = "true";
      OPENAI_BASE_URL = "https://api.z.ai/api/coding/paas/v4";
      BUZZ_AUTH_TAG = ''["auth","93984b5c44debc12757e0f5db1643c2808ee8b820b46ac704febb039de4c16a7","","a5b2da36a39eb7569f10e823ecb699cf0ccef495149cdca5144118f0d751efdc636d2f707b90c7a9ae6e92355453283433edf33678af21ca3c6aa481cb48d961"]'';
    };

    environmentFiles = [
      config.age.secrets.hermes-bee-env.path
    ];

    # buzz CLI for outbound message delivery
    extraPackages = [ buzz ];
  };

  # Inject secrets directly into the systemd service environment so the
  # Hermes runtime provider resolver sees OPENAI_API_KEY before python-dotenv
  # loads .env. Without this, the resolver falls back to "no-key-required".
  systemd.services.hermes-agent.serviceConfig.EnvironmentFile = [
    config.age.secrets.hermes-bee-env.path
  ];

  # ── Beszel monitoring agent ────────────────────────────────────
  # (enabled by default in modules/beszel-agent.nix)

  # (Firewall disabled — no per-service port openings needed)

  # ── State version ───────────────────────────────────────────────
  system.stateVersion = "25.11";
}

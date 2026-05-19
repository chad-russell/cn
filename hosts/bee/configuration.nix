# ── bee: Beelink Mini PC ───────────────────────────────────────────
#
# NixOS install on Crucial P3 Plus 1TB NVMe, 32GB RAM.
# General-purpose server — services to be added incrementally.

{ config, lib, pkgs, unstable, ... }:

{
  imports = [
    ../../modules/base-server.nix
    ../../modules/hub-disk-config.nix
    ../../modules/nebula-client.nix
    ../../modules/pi-agent.nix
    ../../modules/opencode.nix
    # ./adguardhome.nix  # paused — not needed with distrobox workflow
    ./caddy-dev.nix
    ./gloo-dev.nix
    ./buildspace.nix
    ./pipane.nix
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
  hardware.enableRedistributableFirmware = true;
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
  services.nebula.networks.homelab.enable = true;

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

  # Lighthouse needs UDP 4243 open
  networking.firewall.allowedUDPPorts = [ 4243 ];

  # ┌──────────────────────────────────────────────────────────────────┐
  # │ TEMPORARY: Docker daemon for project work.                       │
  # │                                                                  │
  # │ TO REMOVE later, delete everything between the ┌┐/└┘ boxes,    │
  # │ then:  nix run .#deploy -- bee                                   │
  # │ and on bee:  sudo systemctl stop docker containerd               │
  # │              sudo rm -rf /var/lib/docker   # if no longer needed │
  # │                                                                  │
  # │ SIDE EFFECTS of this change:                                     │
  # │  - dockerCompat disabled (mkForce false); revert to use Podman   │
  # │    wrapper again. gloo-dev/buildspace set it independently.       │
  # │  - crussell added to "docker" group (needs re-login to take      │
  # │    effect; or: newgrp docker)                                     │
  # │  - DOCKER_HOST in any devshell flake.nix that points to Podman   │
  # │    may need updating for Docker-based projects (e.g. DDEV).      │
  # └──────────────────────────────────────────────────────────────────┘
  virtualisation.docker.enable = true;
  # Disable dockerCompat — conflicts with real Docker. Gloo and Buildspace
  # explicitly use `podman` or set DOCKER_HOST to the Podman socket, so they
  # don't need the `docker` → `podman` wrapper.
  virtualisation.podman.dockerCompat = lib.mkForce false;
  # Append "docker" group to existing groups ("wheel" from base-server.nix).
  # Uses mkAfter to avoid conflicting with the base-server definition.
  users.users.crussell.extraGroups = lib.mkAfter [ "docker" ];
  # ┌──────────────────────────────────────────────────────────────────┐
  # │ END TEMPORARY DOCKER                                             │
  # │                                                                  │
  # │ NOTE: When removing, also revert dockerCompat back to true in    │
  # │ gloo-dev.nix and buildspace.nix (they set it individually, but  │
  # │ mkForce false here overrides both). Or just remove this line and │
  # │ the modules will set dockerCompat = true again automatically.    │
  # └──────────────────────────────────────────────────────────────────┘

  # ── nix-ld — run dynamically-linked foreign binaries (npm/bun globals) ─
  programs.nix-ld.enable = true;

  # ── Dev tools ───────────────────────────────────────────────────
  environment.systemPackages = [
    pkgs.git
    pkgs.github-cli
  ];

  # ── pi coding agent ──────────────────────────────────────────
  services.pi-agent.enable = true;

  # ── opencode AI coding agent ────────────────────────────────────
  services.opencode.enable = true;
  services.opencode.web.enable = true;

  # Firewall ports managed by gloo-dev and buildspace modules

  # ── Dev stacks ──────────────────────────────────────────────────
  # Gloo repos run in their own devcontainers via plain podman compose.
  # gloo-dev installs override files + skill; buildspace provides
  # podman/docker-compose/user-linger.
  services.gloo-dev.enable = true;
  services.buildspace.enable = true;

  # ── State version ───────────────────────────────────────────────
  system.stateVersion = "25.11";
}

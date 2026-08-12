# ── bees: AMD Ryzen AI MAX+ 395 Production Server ──────────────────
#
# AMD Ryzen AI MAX+ 395 w/ Radeon 8060S, 16C/32T
# 128 GB RAM (shared with iGPU; ~32 GB visible to OS)
# 2 TB NVMe (Crucial P310), dual Intel E610 10GbE
# Active NIC: enp196s0f1 (second port; enp196s0f0 is unplugged)

{ config, lib, pkgs, unstable, ... }:

{
  imports = [
    ../../modules/base-server.nix
    ../../modules/freshness-checks.nix
    ./disk-config.nix
    ../../modules/nebula-client.nix
    ../../modules/opencode.nix
    ./gloo-proxy.nix
    ./media-services.nix
    ./immich.nix
    ./immich-backup.nix
    ./ntfy.nix
    ./datenight.nix
    ./caddy.nix
    ./services.nix
    ./llama-server.nix
    ./backup.nix
    ./beszel.nix
  ];

  networking.hostName = "bees";

  # ── Essential packages ────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [ ];

  # ── Boot ─────────────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usbhid"
    "sd_mod"
    # Intel E610 10GbE NIC driver
    "ixgbe"
  ];
  boot.initrd.kernelModules = [ "ixgbe" ];
  boot.kernelModules = [ "kvm-amd" ];

  # Use latest kernel (7.0.x) — the default 6.12 ixgbe module doesn't
  # recognize the Intel E610 (8086:57b0) NIC on this machine.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # ── Hardware ─────────────────────────────────────────────────────
  hardware.cpu.amd.updateMicrocode =
    lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.enableRedistributableFirmware = lib.mkForce true;
  hardware.enableAllFirmware = true;
  zramSwap.enable = true;

  # ── nix-ld — run dynamically-linked foreign binaries (npm/bun globals) ─
  programs.nix-ld.enable = true;

  # ── Cargo bin on PATH ─────────────────────────────────────────────
  programs.zsh.interactiveShellInit = ''
    path+=("$HOME/.cargo/bin")
  '';

  # ── Networking ───────────────────────────────────────────────────
  # Intel E610 dual-port 10GbE — active port is the second function
  # PCI slot: 0000:c4:00.1, MAC: 78:55:36:02:ce:bf
  #
  # Match by MAC address so the network comes up regardless of what
  # predictable name systemd-udevd assigns.
  systemd.network.networks."40-lan" = {
    matchConfig.MACAddress = "78:55:36:02:ce:bf";
    networkConfig.DHCP = "no";
    address = [ "192.168.20.41/24" ];
    routes = [{ Gateway = "192.168.20.1"; }];
    dns = [ "8.8.8.8" "1.1.1.1" ];
  };

  # ── NFS: Media from NAS ─────────────────────────────────────────
  fileSystems."/mnt/media" = {
    device = "192.168.20.31:/pool/media";
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

  # ── NFS: Photos from NAS ────────────────────────────────────────
  fileSystems."/mnt/photos" = {
    device = "192.168.20.31:/pool/photos";
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

  # ── opencode AI coding agent ────────────────────────────────────
  # (enable + web defaults live in modules/opencode.nix)

  # ── Gloo AI Proxy ──────────────────────────────────────────────────
  services.gloo-proxy.enable = true;

  # ── Firewall: disabled (router handles it) ───────────────────────
  networking.firewall.enable = false;

  # ── Podman (for Caddy + service containers) ─────────────────
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  # ── Monitoring ───────────────────────────────────────────────────
  # Alert if the internal wildcard cert stops renewing (Route53 DNS challenge
  # via Caddy in a container). Check the live cert on localhost.
  homelab.freshnessChecks.bees-cert = {
    description = "bees internal TLS cert";
    extraPath = [ pkgs.openssl ];
    checkCommand = ''
      host=linkding.internal.crussell.io
      end=$(echo | openssl s_client -connect localhost:443 -servername "$host" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
      [ -n "$end" ] || { echo "could not read cert for $host"; exit 1; }
      days=$(( ($(date -d "$end" +%s) - $(date +%s)) / 86400 ))
      echo "$host cert valid ''${days}d"
      [ "$days" -gt 14 ]
    '';
  };

  # Surface prolonged failures of the most critical services (they auto-restart,
  # so this only fires when the restart limit is exhausted).
  #
  # immich-server is a native NixOS module, so a normal `systemd.services`
  # override merges cleanly into its generated unit.
  systemd.services.immich-server.onFailure =
    [ "ntfy-failure@immich-server.service" ];

  # caddy is a podman quadlet — its unit comes from the podman-system-generator
  # at /run/systemd/generator/caddy.service, NOT from NixOS. Setting
  # `systemd.services.caddy.*` makes NixOS write a stub caddy.service (no
  # ExecStart) that shadows the generator output and breaks `systemctl restart`.
  # Ship a drop-in via systemd.packages so it layers on the generated unit
  # instead of replacing it.
  systemd.packages = [
    (pkgs.runCommand "caddy-on-failure-dropin" { } ''
      mkdir -p $out/etc/systemd/system/caddy.service.d
      cat > $out/etc/systemd/system/caddy.service.d/10-on-failure.conf <<'EOF'
      [Unit]
      OnFailure=ntfy-failure@caddy.service
      EOF
    '')
  ];

  # ── State version ───────────────────────────────────────────────
  system.stateVersion = "25.11";
}

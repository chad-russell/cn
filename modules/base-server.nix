# ── Base Server Configuration ──────────────────────────────────────
#
# Shared config for all server hosts (bee, bees).
# Thinkpad is NOT a server and has its own config.

{ config, lib, pkgs, unstable, ... }:

{
  ## Single ntfy topic for ALL homelab alerts — subscribe once to this.
  ## (Consumed by modules/freshness-checks.nix and modules/restic-backup.nix.)
  options.homelab.ntfyUrl = lib.mkOption {
    type = lib.types.str;
    default = "https://ntfy.internal.crussell.io/homelab-alerts";
    description = "ntfy topic for all homelab alerts.";
  };

  imports = [
    ./server-shell.nix
    ./nebula-hosts.nix
  ];

  # ── Time / Locale ────────────────────────────────────────────────
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # ── Users ────────────────────────────────────────────────────────
  users.users.crussell = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOpNEpdHo8X0L9rgsJ+8fuXA4DodZftJaCd3Q6eCrVsw crussell@fedora"
    ];
    initialPassword = "changeme";
  };
  security.sudo.wheelNeedsPassword = false;

  # Root SSH keys (for nixos-anywhere and emergency access)
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOpNEpdHo8X0L9rgsJ+8fuXA4DodZftJaCd3Q6eCrVsw crussell@fedora"
  ];

  # ── SSH ──────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = true;
    };
  };

  # ── Networking (systemd-networkd) ────────────────────────────────
  systemd.network.enable = true;
  networking.useDHCP = false;
  networking.nameservers = [ "8.8.8.8" "1.1.1.1" ];
  networking.enableIPv6 = false;

  # ── Base packages ────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    htop
    jq
    ethtool
    nfs-utils
    ripgrep
    fd
    unstable.cursor-cli
  ];

  # ── Allow unfree packages ────────────────────────────────────────
  nixpkgs.config.allowUnfree = true;

  # ── Nix settings ─────────────────────────────────────────────────
  nix.settings.trusted-users = [ "root" "crussell" ];
  nix.settings.auto-optimise-store = true;

  # Per-user nix profile dir home-manager activates into. Must exist before
  # home-manager-crussell.service runs; absent on hosts that never had
  # home-manager (e.g. a fresh nas/gateway), which fails first activation.
  systemd.tmpfiles.rules = [
    "d /nix/var/nix/profiles/per-user/crussell 0755 crussell users -"
  ];

  boot.loader.systemd-boot.configurationLimit = 15;
  boot.loader.grub.configurationLimit = 15;

  # ── Firmware (shared by all hosts; bees/gateway mkForce for
  #    enableAllFirmware/microcode interactions) ─────────────────────
  hardware.enableRedistributableFirmware = true;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    persistent = true;
    randomizedDelaySec = "10m";
  };

  systemd.services.nix-gc.preStart = ''
    ${config.nix.package.out}/bin/nix-env --delete-generations +15 -p /nix/var/nix/profiles/system
  '';

  # ── Agenix: decrypt secrets at boot ────────────────────────────────
  # The identity lives under the user's $HOME, so any host that mounts /home
  # as a SEPARATE filesystem MUST mark it `neededForBoot = true` (already done
  # in hosts/{bees,nas,bee}/disk-config.nix).
  # Otherwise /home mounts after activation and every age secret silently
  # fails to decrypt on reboot — which took down Caddy (and thus all public
  # routes incl. homeassistant.crussell.io) on bees after the 2026-06-13 power
  # outage. Gateway is unaffected: it keeps /home on the single ext4 root fs.
  age.identityPaths = [ "/home/crussell/.config/age/key.txt" ];

  # ── NFS client support ───────────────────────────────────────────
  services.rpcbind.enable = true;
}

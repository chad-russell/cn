{
  config,
  pkgs,
  username,
  unstable,
  ...
}:
{
  # ── Boot ──────────────────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 15;
  boot.loader.efi.canTouchEfiVariables = true;

  # ── Kernel ────────────────────────────────────────────────────────────
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # ── Kernel parameters for power saving ────────────────────────────────
  # Note: nixos-hardware already adds acpi_backlight=native and touchpad fix
  boot.kernelParams = [
    "mem_sleep_default=deep"            # Use s2idle (S0ix) for modern standby
    "usbcore.autosuspend=2"             # USB autosuspend after 2s (replaces TLP)
    "pcie_aspm=force"                   # Force PCIe ASPM even if BIOS doesn't advertise
  ];

  # Reduce swap aggression — prevents long-running apps (e.g. Ghostty) from
  # being slowly pushed to swap and causing I/O stalls when paged back in.
  boot.kernel.sysctl = { "vm.swappiness" = 10; };

  # ── Networking ────────────────────────────────────────────────────────
  networking.hostName = "think";
  networking.enableIPv6 = false;
  networking.networkmanager.enable = true;

  # NetworkManager VPN plugins
  # - OpenConnect: Palo Alto GlobalProtect (Wycliffe) and generic GP portals
  networking.networkmanager.plugins = [ pkgs.networkmanager-openconnect ];

  # ── Split DNS: *.dev.crussell.io via AdGuardHome on bee (Nebula) ───
  # Routes dev domain queries through Nebula to AdGuardHome on bee.
  # All other DNS uses the default resolver.
  services.resolved = {
    enable = true;
    settings.Resolve = {
      DNS = [ "10.10.0.12" ];
      Domains = [ "~dev.crussell.io" ];
    };
  };

  # ── KDE Connect (phone↔desktop integration) ──────────────────────────
  programs.kdeconnect.enable = true;

  # ── LocalSend file sharing (port 53317 TCP+UDP) ──────────────────────
  networking.firewall.allowedTCPPorts = [ 53317 ];
  networking.firewall.allowedUDPPorts = [ 53317 ];

  # ── Time & Locale ─────────────────────────────────────────────────────
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # ── nix-ld — run dynamically-linked foreign binaries (npm/bun globals) ─
  programs.nix-ld.enable = true;

  # ── Zsh ───────────────────────────────────────────────────────────────
  programs.zsh.enable = true;

  # ── Users ─────────────────────────────────────────────────────────────
  users.users.${username} = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
      "input"
      "docker"
    ];
    # subuid/subgid for rootless podman (enables --userns=keep-id).
    subUidRanges = [{ startUid = 100000; count = 65536; }];
    subGidRanges = [{ startGid = 100000; count = 65536; }];
    # Change this or use initialPassword / hashedPassword
    initialPassword = "temp";
  };

  # ── SSH ──────────────────────────────────────────────────────────────
  services.openssh.enable = true;

  # ── opencode AI coding agent ────────────────────────────────────────
  services.opencode.enable = true;

  # ── Nebula VPN ─────────────────────────────────────────────────────
  services.nebula.networks.homelab = {
    enable = true;
    tun.device = "nebula0";
  };

  # Ensure the nebula service user can read the cert/key files
  # (systemd runs as nebula-homelab:nebula-homelab)
  # NOTE: cert tmpfiles rules are now provided by modules/nebula-client.nix
  systemd.tmpfiles.rules = [

    # GlobalProtect-openconnect still execs a few FHS paths internally.
    "L+ /usr/bin/gpclient - - - - ${pkgs.globalprotect-openconnect}/usr/bin/gpclient"
    "L+ /usr/bin/gpservice - - - - ${pkgs.globalprotect-openconnect}/usr/bin/gpservice"
    "L+ /usr/bin/gpauth - - - - ${pkgs.globalprotect-openconnect}/usr/bin/gpauth"
    "L+ /usr/bin/gpgui - - - - ${pkgs.globalprotect-openconnect}/usr/bin/gpgui"
    "L+ /usr/bin/gpgui-helper - - - - ${pkgs.globalprotect-openconnect}/usr/bin/gpgui-helper"
    "L+ /usr/libexec/gpclient/vpnc-script - - - - ${pkgs.globalprotect-openconnect}/usr/libexec/gpclient/vpnc-script"
    "L+ /usr/libexec/gpclient/hipreport.sh - - - - ${pkgs.globalprotect-openconnect}/usr/libexec/gpclient/hipreport.sh"
  ];

  # ── Keyboard: Caps Lock ↔ Escape ────────────────────────────────────
  # System-wide XKB default.  GNOME and KWin read from the system XKB
  # directory on Wayland.  Niri overrides this in its own config.kdl.
  services.xserver.xkb = {
    layout = "us";
    options = "caps:swapescape";
  };

  # ── Niri — scrollable-tiling Wayland compositor ───────────────────────
  programs.niri.enable = true;



  # ── GNOME — full desktop environment ──────────────────────────────────
  # Provides a complete Wayland DE alongside niri. GDM offers session
  # selection at login so you can pick GNOME or niri.
  services.xserver.desktopManager.gnome.enable = true;
  services.xserver.displayManager.gdm.enable = true;


  # Exclude default GNOME apps we don't need (already have alternatives)
  environment.gnome.excludePackages = with pkgs; [
    gnome-tour
    epiphany           # browser (have zen)
    geary              # email
    gnome-contacts
    gnome-maps
    gnome-music
    gnome-photos
    gnome-weather
    totem              # video player
    yelp               # help viewer
    simple-scan
  ];

  # ── Noctalia v5 ─────────────────────────────────────────────────────
  # Installed and configured via Home Manager module (programs.noctalia).

  # Required by Noctalia for battery, bluetooth features
  services.upower.enable = true;
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # ── Power profiles (power-profiles-daemon) ───────────────────────────
  # Provides the org.freedesktop.PowerProfiles D-Bus interface used by
  # noctalia-shell's performance/battery/power-saver toggle.
  services.power-profiles-daemon.enable = true;

  # ── Battery charge thresholds (preserves battery lifespan) ────────────
  # Only charges between 75–80%, prevents constant top-up wear.
  # Uses the thinkpad_acpi sysfs interface directly (same mechanism TLP used).
  services.udev.extraRules = ''
    # Set battery charge thresholds when battery device appears
    ACTION=="add", SUBSYSTEM=="power_supply", KERNEL=="BAT0", \
      ATTR{charge_control_start_threshold}="75", \
      ATTR{charge_control_end_threshold}="80"
  '';

  # ── Battery & power saving ───────────────────────────────────────────
  # Replaces TLP's per-subsystem power saving that power-profiles-daemon
  # doesn't cover. power-profiles-daemon handles CPU governor + platform
  # profile; the rules below handle Wi-Fi, PCIe, USB, audio, and NVMe.

  # Wi-Fi power saving on battery (matches TLP's WIFI_PWR_ON_BAT=on)
  networking.networkmanager.connectionConfig = {
    "connection.mdns" = "2";           # resolve mDNS only when needed
  };
  networking.networkmanager.settings = {
    device = {
      "wifi.scan-rand-mac-address" = true;
      "wifi.backend" = "wpa_supplicant";
    };
  };

  # Audio codec power saving (matches TLP's SOUND_POWER_SAVE_ON_BAT=1)
  # snd_hda_intel is loaded for the HDMI codec; SOF handles the main audio
  #
  # iwlwifi: disable power save to prevent firmware crashes on Lunar Lake
  # integrated WiFi (8086:a840 / bz-b0-fm-c0 firmware). Without this the
  # adapter periodically crashes with "SYSTEM_STATISTICS_CMD timeout" →
  # "Device error - SW reset", causing multi-second system freezes.
  boot.extraModprobeConfig = ''
    options snd_hda_intel power_save=1
    options iwlwifi power_save=0
  '';

  # iwlwifi TSO/GSO workaround — Intel Lunar Lake integrated WiFi firmware
  # crashes when TCP/Generic Segmentation Offload is enabled, producing
  # "SYSTEM_STATISTICS_CMD timeout" and "Device error - SW reset" with
  # multi-second system freezes. Disable TSO+GSO every time the interface
  # comes up. See: CachyOS/linux-cachyos#673 for the same bug on BE401.
  networking.networkmanager.dispatcherScripts = [{
    source = pkgs.writeShellScript "disable-iwlwifi-tso.sh" ''
      if [ "$1" = "wlp0s20f3" ] && [ "$2" = "up" ]; then
        ${pkgs.ethtool}/bin/ethtool -K "$1" tso off gso off
      fi
    '';
    type = "basic";
  }];

  # ── Flatpak (for Bazaar app store) ──────────────────────────────────
  services.flatpak.enable = true;

  # ── XDG Desktop Portal ──────────────────────────────────────────────
  # GNOME module provides xdg-desktop-portal-gnome automatically.
  # niri also uses the gnome portal. Add gtk portal for file pickers.
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
    ];
  };

  # ── Firmware updates ──────────────────────────────────────────────────
  services.fwupd.enable = true;

  # ── Thermal management ────────────────────────────────────────────────
  # Intel thermal daemon — proactive cooling, smarter fan curves,
  # prevents sudden throttling under sustained load on Lunar Lake.
  services.thermald.enable = true;

  # ── Audio ─────────────────────────────────────────────────────────────
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # ── Essential packages ────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    # Wayland essentials (brightnessctl, playerctl, wl-clipboard now in hod profile)
    wireplumber
    xwayland-satellite
    grim
    slurp
    bibata-cursors

    # Apps (swap these for your preferences)
    ghostty
    nautilus

    # Fonts
    fontconfig
    nerd-fonts.jetbrains-mono

    # AI / dev tools
    pi-coding-agent
    antigravity-cli

    # 3D printing
    bambu-studio

    # VM management
    incus               # incus client for remote hypervisor access
    virt-viewer         # SPICE graphical console for VMs

    # VPN — Palo Alto GlobalProtect (Wycliffe)
    # Wycliffe's gpcloudservice portal requires CAS/SAML. Use either:
    #   gpauth wycliffe.gpcloudservice.com --browser zen 2>/dev/null \
    #     | sudo gpclient connect wycliffe.gpcloudservice.com --cookie-on-stdin
    # or:
    #   sudo -E gpclient connect wycliffe.gpcloudservice.com --browser zen
    # Keep OpenConnect + gp-saml-gui as fallbacks for other GP portals.
    openconnect
    gp-saml-gui
    globalprotect-openconnect

    # VPN — Proton VPN (personal)
    # GTK GUI app with full feature support: Kill Switch, NetShield, split tunneling,
    # WireGuard, VPN Accelerator, etc. Requires: NetworkManager (enabled),
    # gnome-keyring (enabled), systemd-resolved (enabled for split tunneling).
    # Start from app launcher as "Proton VPN" or run `protonvpn-app`.
    protonvpn-gui
    proton-vpn-cli

    # Passwords — Proton Pass CLI
    # Manage vaults, items, and secrets from the terminal.
    # Run `proton-pass` to get started.
    proton-pass-cli

    (pkgs.writeShellScriptBin "oc-attach" ''
      case "$1" in
        bee)  exec opencode attach http://10.10.0.12:4096 ;;
        bees) exec opencode attach http://10.10.0.6:4096 ;;
        *)    echo "Usage: oc-attach <bee|bees>" >&2; exit 1 ;;
      esac
    '')
  ];

  # ── Fonts ─────────────────────────────────────────────────────────────
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    xorg.fontadobe75dpi
    xorg.fontadobe100dpi
  ];

  # ── Libvirt (VM management) ───────────────────────────────────────────
  virtualisation.libvirtd.enable = true;
  virtualisation.libvirtd.qemu.package = pkgs.qemu;

  # ── Containers ─────────────────────────────────────────────────────────
  # Rootless podman, owned by NixOS (moved off the hod profile).
  # Provides a known-good integrated stack: podman, crun, conmon,
  # passt/netavark for rootless networking, and containers/storage config.
  virtualisation.podman = {
    enable = true;
    # Pin a default registry so short names like `fedora:latest` resolve.
    defaultNetwork.settings = {
      dns_enabled = true;
    };
  };

  # Rootless podman runtime (crun is lightweight and rootless-friendly).
  virtualisation.podman.extraPackages = [ pkgs.crun ];

  # ── Agenix identity ────────────────────────────────────────────────────
  # Secrets (restic backups, etc.) are encrypted for the user's age key,
  # not the SSH host key. Match modules/base-server.nix used by other hosts.
  age.identityPaths = [ "/home/${username}/.config/age/key.txt" ];

  # Docker is enabled separately for workloads that require the real Docker
  # daemon/CLI instead of a podman-compatible wrapper.
  virtualisation.docker.enable = true;

  # ── Gnome keyring ─────────────────────────────────────────────────────
  services.gnome.gnome-keyring.enable = true;

  # ── D-Bus ─────────────────────────────────────────────────────────────
  services.dbus.enable = true;

  # ── Allow unfree packages ────────────────────────────────────────────────
  nixpkgs.config.allowUnfree = true;

  # Bluetooth GUI for pairing + system tray applet
  services.blueman.enable = true;

  # ── NFS: Backups to NAS ───────────────────────────────────────────
  # Used by restic for local backup copy (homelab-backup NAS target)
  fileSystems."/mnt/backups" = {
    device = "192.168.20.31:/pool/backups";
    fsType = "nfs";
    options = [ "x-systemd.automount" "noauto" "timeo=14" "nfsvers=4" "rw" "soft" "intr" ];
  };

  # ── Trust Caddy internal CA from bee ──────────────────────────────
  # After deploying bee and starting Caddy, extract the root CA:
  #   ssh bee 'sudo cat /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt' \
  #     > thinkpad/certs/bee-caddy-root.pem
  # Then rebuild the laptop.
  security.pki.certificateFiles = [ ./certs/bee-caddy-root.pem ];

  # ── Nix settings ──────────────────────────────────────────────────────
  nix.settings.trusted-users = [ "root" "@wheel" ];
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Binary caches
  nix.settings.extra-substituters = [
    "https://vicinae.cachix.org"
    "https://noctalia.cachix.org"
  ];
  nix.settings.extra-trusted-public-keys = [
    "vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc="
    "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
  ];

  # ── Garbage collection ────────────────────────────────────────────────
  nix.gc = {
    automatic = true;
    dates = "weekly";
    persistent = true;          # catch up on missed runs at boot
    randomizedDelaySec = "10m"; # spread load across machines
  };

  systemd.services.nix-gc.preStart = ''
    ${config.nix.package.out}/bin/nix-env --delete-generations +15 -p /nix/var/nix/profiles/system
  '';

  # ── Nix store optimisation ────────────────────────────────────────────
  # Deduplicate store paths on every build
  nix.settings.auto-optimise-store = true;

  # Keep derivation metadata useful for queries
  nix.settings.keep-outputs = true;
  nix.settings.keep-derivations = true;

  # ── Prometheus node exporter (for homelab monitoring) ──────────
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    openFirewall = true;
  };

  # ── State version ─────────────────────────────────────────────────────
  system.stateVersion = "25.11";

  # ── Home Manager settings ─────────────────────────────────────────────
  home-manager.backupFileExtension = "hm-backup";
}

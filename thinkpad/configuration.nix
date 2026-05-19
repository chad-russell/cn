{
  config,
  pkgs,
  username,
  hyprland,
  ...
}:
{
  # ── Boot ──────────────────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
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
  networking.networkmanager.enable = true;

  # Palo Alto GlobalProtect VPN support (Wycliffe)
  # Keep the NetworkManager/OpenConnect plugin for generic GP portals, but
  # Wycliffe's gpcloudservice portal uses CAS/SAML and works more reliably with
  # the packaged `gpclient` / `gpauth` tools below.
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
    ];
    # Change this or use initialPassword / hashedPassword
    initialPassword = "temp";
  };

  # ── SSH ──────────────────────────────────────────────────────────────
  services.openssh.enable = true;

  # ── Nebula VPN ─────────────────────────────────────────────────────
  services.nebula.networks.homelab = {
    enable = true;
    ca = "/etc/nebula/ca.crt";
    cert = "/etc/nebula/host.crt";
    key = "/etc/nebula/host.key";

    staticHostMap = {
      "10.10.0.1" = [ "192.168.20.105:4243" ];  # bee (local lighthouse)
      "10.10.0.2" = [ "178.156.171.212:4242" ];
    };

    isLighthouse = false;
    isRelay = false;
    lighthouses = [ "10.10.0.1" "10.10.0.2" ];
    relays = [ "10.10.0.2" ];

    listen.host = "0.0.0.0";
    listen.port = null; # 0 for non-lighthouse/relay

    tun.disable = false;
    tun.device = "nebula0";

    firewall.outbound = [{ port = "any"; proto = "any"; host = "any"; }];
    firewall.inbound  = [{ port = "any"; proto = "any"; host = "any"; }];

    settings = {
      punchy = { punch = true; respond = true; };
      preferred_ranges = [ "192.168.20.0/24" ];
      logging = { level = "info"; format = "text"; };
      lighthouse.interval = 60;
      firewall.conntrack = {
        tcp_timeout = "120h";
        udp_timeout = "3m";
        default_timeout = "10m";
        max_connections = 100000;
      };
    };
  };

  # Ensure the nebula service user can read the cert/key files
  # (systemd runs as nebula-homelab:nebula-homelab)
  systemd.tmpfiles.rules = [
    "Z /etc/nebula/ca.crt  0440 root nebula-homelab -"
    "Z /etc/nebula/host.crt 0440 root nebula-homelab -"
    "Z /etc/nebula/host.key 0440 root nebula-homelab -"

    # GlobalProtect-openconnect still execs a few FHS paths internally.
    "L+ /usr/bin/gpclient - - - - ${pkgs.globalprotect-openconnect}/usr/bin/gpclient"
    "L+ /usr/bin/gpservice - - - - ${pkgs.globalprotect-openconnect}/usr/bin/gpservice"
    "L+ /usr/bin/gpauth - - - - ${pkgs.globalprotect-openconnect}/usr/bin/gpauth"
    "L+ /usr/bin/gpgui - - - - ${pkgs.globalprotect-openconnect}/usr/bin/gpgui"
    "L+ /usr/bin/gpgui-helper - - - - ${pkgs.globalprotect-openconnect}/usr/bin/gpgui-helper"
    "L+ /usr/libexec/gpclient/vpnc-script - - - - ${pkgs.globalprotect-openconnect}/usr/libexec/gpclient/vpnc-script"
    "L+ /usr/libexec/gpclient/hipreport.sh - - - - ${pkgs.globalprotect-openconnect}/usr/libexec/gpclient/hipreport.sh"
  ];

  # ── Niri — scrollable-tiling Wayland compositor ───────────────────────
  programs.niri.enable = true;

  # ── Hyprland — tiling Wayland compositor (Lua config, 0.55+) ──────────
  # Start from TTY with `Hyprland`. Coexists with niri.
  programs.hyprland = {
    enable = true;
    package = hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    portalPackage = hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
  };

  # ── Mango — dwm-like Wayland compositor with scroller layout ──────────
  # Start from TTY with `mangowc` wrapper or `mango`. Coexists with niri/hyprland.
  # NixOS module handles XDG portal (wlr), polkit, XWayland, and login entry.
  # Home-manager module handles config, autostart, and systemd session target.
  programs.mango.enable = true;

  # ── Noctalia Shell ────────────────────────────────────────────────────
  services.noctalia-shell.enable = true;

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

  # Bluetooth GUI for pairing + system tray applet
  services.blueman.enable = true;

  # ── XDG Desktop Portal ──────────────────────────────────────────────
  # niri uses gnome portal.
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gnome
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
    # Wayland essentials
    wl-clipboard
    brightnessctl
    playerctl
    wireplumber
    xwayland-satellite
    grim
    slurp
    bibata-cursors

    # Apps (swap these for your preferences)
    ghostty
    fuzzel
    swaylock
    nautilus

    # Fonts
    fontconfig
    nerd-fonts.jetbrains-mono

    # AI / dev tools
    pi-coding-agent
    opencode

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

  # ── Podman (rootless containers) ──────────────────────────────────────
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;    # provides `docker` alias via podman
    defaultNetwork.settings.dns_enabled = true;
  };

  # ── Flatpak ──────────────────────────────────────────────────────────
  services.flatpak.enable = true;

  # ── Gnome keyring ─────────────────────────────────────────────────────
  services.gnome.gnome-keyring.enable = true;

  # ── D-Bus ─────────────────────────────────────────────────────────────
  services.dbus.enable = true;

  # ── Allow unfree packages ────────────────────────────────────────────────
  nixpkgs.config.allowUnfree = true;



  # ── NFS: Backups to NAS ───────────────────────────────────────────
  # Used by restic for local backup copy (homelab-backup NAS target)
  fileSystems."/mnt/backups" = {
    device = "192.168.20.31:/mnt/tank/backups";
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
    "https://hyprland.cachix.org"
  ];
  nix.settings.extra-trusted-public-keys = [
    "vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc="
    "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
  ];

  # ── Garbage collection ────────────────────────────────────────────────
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
    persistent = true;          # catch up on missed runs at boot
    randomizedDelaySec = "10m"; # spread load across machines
  };

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
}

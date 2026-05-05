{
  config,
  pkgs,
  username,
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

  # ── Networking ────────────────────────────────────────────────────────
  networking.hostName = "think";
  networking.networkmanager.enable = true;

  # ── Time & Locale ─────────────────────────────────────────────────────
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

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

  # ── Nebula VPN ──────────────────────────────────────────────────────
  services.nebula.networks.homelab = {
    enable = true;
    ca = "/etc/nebula/ca.crt";
    cert = "/etc/nebula/host.crt";
    key = "/etc/nebula/host.key";

    staticHostMap = {
      "10.10.0.1" = [ "192.168.20.105:4243" ];
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
  ];

  # ── Niri — scrollable-tiling Wayland compositor ───────────────────────
  programs.niri.enable = true;

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
  boot.extraModprobeConfig = ''
    options snd_hda_intel power_save=1
  '';

  # Bluetooth GUI for pairing + system tray applet
  services.blueman.enable = true;

  # ── XDG Desktop Portal (needed for niri screen sharing, etc.) ────────
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gnome
    ];
  };

  # ── Firmware updates ──────────────────────────────────────────────────
  services.fwupd.enable = true;

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
  ];

  # ── Fonts ─────────────────────────────────────────────────────────────
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
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



  # ── Nix settings ──────────────────────────────────────────────────────
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Vicinae cachix
  nix.settings.extra-substituters = [ "https://vicinae.cachix.org" ];
  nix.settings.extra-trusted-public-keys = [ "vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc=" ];

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

  # ── State version ─────────────────────────────────────────────────────
  system.stateVersion = "25.11";
}

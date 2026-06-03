{ pkgs, ... }:
{
  # ── Minimal KDE Plasma 6 — Zoom screen sharing ──────────────────────
  #
  # The existing niri/mangowc compositors have unreliable PipeWire
  # screen sharing.  Plasma Wayland + xdg-desktop-portal-kde handles
  # window/desktop selection and streaming reliably.
  #
  # Usage:
  #   1. Log in on TTY as normal.
  #   2. Run `startplasma-wayland` to enter a Plasma session.
  #   3. Launch Zoom (flatpak run us.zoom.Zoom) and share your screen.
  #   4. Log out when done — return to niri/mangowc/COSMIC on next login.
  #
  # All optional KDE applications are stripped.  Your existing apps
  # (ghostty, nautilus, grim/slurp, fuzzel) work inside Plasma.
  #
  # Panel (taskbar) troubleshooting:
  #   The default panel should appear automatically on first login.
  #   If it doesn't (e.g. stale config from a previous Plasma session),
  #   delete the panel config and re-login:
  #     rm ~/.config/plasma-org.kde.plasma.desktop-appletsrc
  #   Or right-click the desktop → Add Panel → Default Panel.

  services.desktopManager.plasma6 = {
    enable = true;
    enableQt5Integration = false;  # Pure Qt6 — no legacy integration needed
  };

  # Strip every optional KDE app — keep only the desktop shell (kwin,
  # plasma-workspace, systemsettings, breeze theme, polkit agent, etc.)
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    ark                         # archive manager
    aurorae                     # window decoration themes
    baloo-widgets               # dolphin baloo integration
    discover                    # software center (use flatpak CLI)
    dolphin                     # file manager (you have nautilus)
    dolphin-plugins             # dolphin extras
    elisa                       # music player
    ffmpegthumbs                # video thumbnails
    gwenview                    # image viewer
    kate                        # text editor
    khelpcenter                 # help documentation
    krdp                        # remote desktop server
    ktexteditor                 # kate runtime
    konsole                     # terminal (you have ghostty)
    okular                      # document viewer
    plasma-browser-integration  # browser extension
    plasma-workspace-wallpapers # extra wallpapers
    spectacle                   # screenshots (you have grim)
    kwin-x11                    # X11 backend (Wayland only)
  ];

  # No KDE PIM (akonadi, kdepim-runtime) — not needed for screen sharing
  programs.kde-pim.enable = false;

  # ── Keyboard: Caps Lock ↔ Escape ────────────────────────────────────
  #
  # System-wide XKB default.  KWin reads from the system XKB directory
  # on Wayland.  Niri and mango override this in their own configs.
  services.xserver.xkb = {
    layout = "us";
    options = "caps:swapescape";
  };

  # Also set it in KDE's own keyboard config so kxkb picks it up.
  # KConfig merges /etc/xdg/ defaults with ~/.config/ user overrides.
  environment.etc."xdg/kxkbrc" = {
    text = ''
      [Layout]
      LayoutList=us
      Options=caps:swapescape
      ResetOldOptions=true
      Use=true
    '';
  };

  # ── Natural scrolling ───────────────────────────────────────────────
  #
  # KDE Plasma stores touchpad settings per-device in kcminputrc under
  # [Libinput][vendor][product][name] sections, making it impossible to
  # set declaratively without knowing the exact device path.
  #
  # As a best-effort default, enable natural scrolling for the mouse
  # section.  For the touchpad specifically, toggle it once manually:
  #   System Settings → Touchpad → Natural Scrolling
  environment.etc."xdg/kcminputrc" = {
    text = ''
      [Mouse]
      NaturalScroll=true
    '';
  };

  # ── Disable KDE Wallet (gnome-keyring handles secrets) ────────────
  #
  # GNOME Keyring provides org.freedesktop.secrets across all sessions
  # (niri, mangowc, COSMIC, KDE).  Disable KWallet so it doesn't conflict
  # over the D-Bus name when running Plasma.
  environment.etc."xdg/kwalletrc" = {
    text = ''
      [Wallet]
      Enabled=false
    '';
  };

  # ── Noctalia: only start with niri ──────────────────────────────────
  #
  # By default the noctalia-shell NixOS module sets
  # WantedBy=graphical-session.target, which starts it in every
  # Wayland session (including KDE).  Change to niri.service so it
  # only activates when niri starts.
  services.noctalia-shell.target = "niri.service";
}

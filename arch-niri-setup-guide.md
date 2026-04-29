# Arch Niri Desktop Setup Guide

Post-install guide for getting your niri desktop environment running on the fresh Arch install. Run all commands as your user (`crussell`) unless prefixed with `sudo`.

## Package Source Summary

| Package | Source | Purpose |
|---|---|---|
| niri | `extra` | Scrollable-tiling Wayland compositor |
| ghostty | `extra` | Terminal emulator |
| fuzzel | `extra` | App launcher (fallback, vicinae replaces it) |
| mako | `extra` | Notification daemon (fallback) |
| swaybg | `extra` | Wallpaper |
| swaylock | `extra` | Screen locker (fallback) |
| waybar | `extra` | Status bar (fallback) |
| xwayland-satellite | `extra` | X11 app support |
| xdg-desktop-portal-gnome | `extra` | Screen sharing |
| xdg-desktop-portal-gtk | `extra` | File picker, etc. |
| cliphist | `extra` | Clipboard history |
| cava | `extra` | Audio visualizer |
| matugen | `extra` | Material color generation |
| wtype | `extra` | Keyboard simulation (voice typing) |
| vulkan-loader | `extra` | GPU acceleration |
| wl-clipboard | `extra` | Wayland clipboard |
| nautilus | `extra` | File manager |
| greetd, greetd-tuigreet | `extra` | Display manager / login greeter |
| noctalia-shell | AUR | Desktop shell (bar, panel, notifications, etc.) |
| noctalia-qs | AUR | Custom Quickshell fork (noctalia-shell dependency) |
| vicinae-bin | AUR | App launcher |

## 1. Enable multilib (optional, for Steam/32-bit)

Only needed if you want Steam or Wine. Skip if you don't care.

```bash
sudo nvim /etc/pacman.conf
```

Uncomment the `[multilib]` section:

```text
[multilib]
Include = /etc/pacman.d/mirrorlist
```

## 2. Install an AUR helper

You'll need to build AUR packages. `paru` is the standard choice:

```bash
sudo pacman -S --needed base-devel git
cd /tmp
git clone https://aur.archlinux.org/paru.git
cd paru
makepkg -si
```

## 3. Install all packages from official repos

One shot:

```bash
sudo pacman -S --needed \
  niri \
  ghostty \
  xwayland-satellite \
  xdg-desktop-portal-gnome \
  xdg-desktop-portal-gtk \
  fuzzel \
  mako \
  swaybg \
  swaylock \
  waybar \
  cliphist \
  cava \
  matugen \
  wtype \
  vulkan-loader \
  wl-clipboard \
  nautilus \
  greetd \
  greetd-tuigreet \
  papirus-icon-theme \
  gnome-keyring
```

## 4. Install AUR packages

```bash
paru -S noctalia-qs noctalia-shell vicinae-bin
```

`noctalia-qs` must be installed before `noctalia-shell` since the shell depends on it. `paru` handles this automatically with the above command.

## 5. Configure greetd (display manager)

greetd + tuigreet is much lighter than GDM and works well with niri.

Edit `/etc/greetd/config.toml`:

```bash
sudo nvim /etc/greetd/config.toml
```

Replace with:

```toml
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --session-command 'niri-session'"
user = "crussell"
```

Enable greetd:

```bash
sudo systemctl enable greetd.service
```

> **Note:** On first boot with greetd, if tuigreet fails to start niri, you may need to check that the niri desktop entry is discoverable:
> ```bash
> ls /usr/share/wayland-sessions/
> ```
> You should see `niri.desktop`. If greetd can't find it, use the full path in the command:
> `command = "tuigreet --time --remember --cmd niri-session"`

## 6. Copy your niri config

Your niri config from the repo at `brunch/config/niri/config.kdl` should go to `~/.config/niri/config.kdl`.

From the repo (on the new system):

```bash
mkdir -p ~/.config/niri
cp /path/to/this/repo/brunch/config/niri/config.kdl ~/.config/niri/config.kdl
```

Or just create it fresh — niri will generate a default config on first launch if the directory doesn't exist, and you can customize from there.

### Config adjustments for Arch

Your current config has these Noctalia-specific keybinds that depend on `noctalia-shell` being installed:

- `Mod+N` → toggle DND (notifications)
- `Mod+Comma` → toggle settings
- `Super+Alt+L` → lock screen
- `Mod+M` → system monitor
- `Mod+Alt+N` → night light toggle
- `Mod+E` → session menu
- Media keys → volume/brightness via Noctalia

These will work once `noctalia-shell` is installed. If you want to test niri before installing Noctalia, you should comment these out or replace them with simpler alternatives (e.g., `swaylock` for locking, `brightnessctl` for brightness).

### Autostart Noctalia

Add to your niri config `~/.config/niri/config.kdl`:

```kdl
spawn-at-startup "qs" "-c" "noctalia-shell"
```

Your config already has `spawn-at-startup "xwayland-satellite"` — just add the Noctalia line after it.

## 7. Environment variables

Create `~/.config/environment.d/niri.conf`:

```bash
mkdir -p ~/.config/environment.d
cat > ~/.config/environment.d/niri.conf <<'EOF'
# XDG spec
XDG_CURRENT_DESKTOP=niri
XDG_SESSION_TYPE=wayland

# Cursor
XCURSOR_THEME=Bibata-Modern-Classic
XCURSOR_SIZE=18
EOF
```

niri-session reads from `~/.config/environment.d/` automatically via systemd.

## 8. Cursor theme

Your config uses `Bibata-Modern-Classic`. Install it:

```bash
paru -S bibata-cursor-theme
```

Or if available in official repos (check first):

```bash
sudo pacman -S bibata-cursor-theme
```

## 9. Fonts

You'll want decent fonts out of the gate:

```bash
sudo pacman -S \
  noto-fonts \
  noto-fonts-emoji \
  ttf-jetbrains-mono \
  ttf-nerd-fonts-symbols
paru -S ttf-jetbrains-mono-nerd
```

Adjust based on what you actually use.

## 10. Polkit authentication agent

Noctalia Shell handles this, but as a fallback:

```bash
sudo pacman -S polkit-gnome
```

Then add to niri autostart if Noctalia isn't handling it:

```kdl
spawn-at-startup "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"
```

## 11. Reboot and test

```bash
sudo reboot
```

After reboot, greetd should show tuigreet. Log in and niri should start.

### First-boot verification

```bash
# Check niri is running
niri msg version

# Check outputs
niri msg outputs

# Verify XWayland satellite is running
pgrep xwayland-satellite

# Check Noctalia is running
pgrep -f "noctalia-shell"

# Test a keybind: Mod+T should open ghostty
```

## 12. Post-desktop setup

Once you have a working desktop, you can continue with:

- **Voxtype**: Your brunch-managed voice-to-text. You'll need to set this up separately since brunch isn't on this system yet.
- **Browser**: Install Chrome via AUR (`google-chrome`) or use `flatpak install com.google.Chrome`
- **Flatpak**: `sudo pacman -S flatpak` if you want Flatpak support
- **Shell**: Your brunch config manages zsh + oh-my-posh. Install manually for now:
  ```bash
  sudo pacman -S zsh
  chsh -s /usr/bin/zsh
  paru -S oh-my-posh
  ```
- **Tailscale**: `sudo pacman -S tailscale` && `sudo systemctl enable --now tailscaled`

## Troubleshooting

### Black screen on niri start

Check if it's a GPU issue:
```bash
niri --session 2>&1 | head -50
```

Intel GPUs should work out of the box. If you see render device issues, check the niri wiki for `debug { render-drm-device }`.

### Noctalia Shell doesn't start

Check Quickshell logs:
```bash
qs -c noctalia-shell 2>&1
```

Make sure `noctalia-qs` (the custom Quickshell fork) is installed, not just the upstream `quickshell` package.

### greetd won't start niri

Check greetd logs:
```bash
sudo journalctl -u greetd
```

Verify the session is discoverable:
```bash
ls /usr/share/wayland-sessions/
```

### Portals not working (screen sharing, etc.)

```bash
# Check portal status
systemctl --user status xdg-desktop-portal
# Restart portals
systemctl --user restart xdg-desktop-portal
```

## Alternative: Skip greetd, use TTY login

If you don't want a display manager at all, you can start niri directly from a TTY:

```bash
niri-session
```

For auto-login without a DM, add to your `.bash_profile` or `.zprofile`:

```bash
if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" -eq 1 ]; then
  exec niri-session
fi
```

This auto-starts niri on virtual terminal 1 when you log in on the TTY.

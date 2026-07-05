# shellbox noctalia

The [noctalia](https://github.com/noctalia-dev/noctalia) desktop shell
(notifications, volume, brightness, nightlight, panels, session lock) in a
shellbox, kept decoupled from the host image because it ships as
`noctalia-git` from the `lionheartp/Hyprland` COPR and updates very
frequently.

Niri stays on the host; noctalia lives here. This is the same model as the
sibling `vicinae` box but with a wider system-integration surface, because
noctalia is a desktop *shell* (it owns D-Bus names, renders layer-shell
panels, and drives hardware through logind), not just a launcher.

## Prepare

```bash
shellbox link ~/Code/cn/hosts/thinkpad/shellboxes/noctalia
shellbox prepare noctalia
```

Ensure `~/.local/share/shellbox/exports/bin` is on your session `PATH`.

## Wire into the host niri config

The export is named `noctalia`, so every existing keybind works unchanged —
niri's `spawn` finds the wrapper via PATH:

```kdl
spawn-at-startup "noctalia"
Mod+N     { spawn "noctalia" "msg" "notification-dnd-toggle"; }
Mod+Comma { spawn "noctalia" "msg" "settings-toggle"; }
Super+Alt+L { spawn "noctalia" "msg" "session" "lock"; }
Mod+M     { spawn "noctalia" "msg" "panel-toggle" "control-center"; }
Mod+Alt+N { spawn "noctalia" "msg" "nightlight-toggle"; }
Mod+E     { spawn "noctalia" "msg" "panel-toggle" "session"; }
XF86AudioRaiseVolume { spawn "noctalia" "msg" "volume-up"; }
XF86AudioLowerVolume { spawn "noctalia" "msg" "volume-down"; }
XF86AudioMute        { spawn "noctalia" "msg" "volume-mute"; }
XF86AudioMicMute     { spawn "noctalia" "msg" "mic-mute"; }
XF86MonBrightnessUp   { spawn "noctalia" "msg" "brightness-up"; }
XF86MonBrightnessDown { spawn "noctalia" "msg" "brightness-down"; }
```

The `layer-rule { match namespace="^noctalia-backdrop" … }` also stays — it's
pure Wayland layer-shell, reachable through the bound `$XDG_RUNTIME_DIR`.

## How it integrates

- **Panels/backdrop/lock surfaces** — Wayland layer-shell, via
  `$XDG_RUNTIME_DIR` (bound by default).
- **Notifications, settings, dconf** — session bus at `$XDG_RUNTIME_DIR/bus`.
  Noctalia shares the host's dconf, so your existing theme/font settings apply
  and its own state persists in `~/.config` across runs.
- **Audio** — PipeWire at `$XDG_RUNTIME_DIR/pipewire-0`.
- **Session lock / brightness / inhibit** — logind (`org.freedesktop.login1`)
  over the **system** bus at `/run/dbus/system_bus_socket`, surfaced via the
  `[[binds]]` (the stock Fedora image has no `/run/dbus`, so the Containerfile
  creates the mount point at build time).

## Update

```bash
shellbox prepare noctalia   # rebuilds the Containerfile (COPR pull), re-materializes
```

## Notes / caveats

- **Verify on first run:**
  1. Does session lock / brightness actually work? That confirms the
     `/run/dbus` system-bus bind is doing its job for logind.
  2. Brightness: if it doesn't change, noctalia may be writing
     `/sys/class/backlight/…/brightness` directly instead of going through
     logind. Fix is either flipping the `/sys` bind to `rw` (and being in the
     `video` group) — but the logind D-Bus path is preferred and already wired.
  3. The `msg`→daemon IPC socket location (assumed under `$XDG_RUNTIME_DIR`,
     same as vicinae).
- **Media-key latency:** holding volume/brightness keys repeats the keybind,
  so each repeat pays a fresh FUSE+namespace setup. Fine for typical use; if
  it ever feels laggy, the lever is a persistent-mount fast path in shellbox,
  not a box-side change.
- **No vendored config:** unlike vicinae, noctalia has no authored file config
  here. It runs from dconf/gsettings defaults and the host's existing
  settings. If a file config becomes needed later, vendor it and add an
  `XDG_CONFIG_HOME` redirect like the vicinae/opencode boxes.

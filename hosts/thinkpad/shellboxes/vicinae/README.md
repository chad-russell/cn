# shellbox vicinae

Bleeding-edge [vicinae](https://vicinae.com) launcher in a shellbox, kept
decoupled from the host image so its fast release cadence doesn't force a
system rebuild. Niri stays on the host; vicinae lives here.

## Prepare

```bash
shellbox link ~/Code/cn/hosts/thinkpad/shellboxes/vicinae
shellbox prepare vicinae
```

Ensure `~/.local/share/shellbox/exports/bin` is on your session `PATH` (once,
globally) so both niri and a shell can resolve the exported `vicinae` wrapper.

## Wire into the host niri config

Because the export is named `vicinae`, the existing keybind lines work
unchanged — niri's `spawn` does PATH lookup and finds the wrapper:

```kdl
spawn-at-startup "vicinae" "server" "--replace"
Mod+Space { spawn "vicinae" "toggle"; }
```

App-launch keybinds, however, must drop `desktoppak-spawn` (apps are now host
binaries, launched directly):

```kdl
Mod+T { spawn "ptyxis"; }                              # was: desktoppak-spawn host /usr/bin/ptyxis
Mod+F { spawn "nautilus" "--new-window"; }             # was: desktoppak-spawn host /usr/bin/nautilus ...
Mod+B { spawn "flatpak" "run" "app.zen_browser.zen"; } # was: desktoppak-spawn flatpak app.zen_browser.zen
```

## How app launching works

Vicinae runs inside the box; the apps it lists live on the host. The vendored
`vicinae-launch` script (set as `launchPrefix` in `settings.json`) bridges the
two by calling `systemd-run --user` — the host's user systemd manager runs the
app on the host, reached through shellbox's bound `$XDG_RUNTIME_DIR` socket.
This is the same host-escape model shellbox's `[host]` tools use, generalized
to arbitrary commands.

## Update vicinae

```bash
shellbox prepare vicinae   # rebuilds the Containerfile (COPR pull), re-materializes
```

## Notes / caveats

- **IPC assumption:** the `toggle` client (one shellbox namespace) reaches the
  `server` daemon (another) over an IPC socket expected to live under
  `$XDG_RUNTIME_DIR`, which shellbox binds through. Verify on first run; if
  vicinae places its socket elsewhere, it will need a config override or a
  `[[binds]]` entry for that path.
- **System-installed flatpaks** may not appear in the list: their `.desktop`
  files live under `/var/lib/flatpak/...`, and shellbox makes `/var` a tmpfs,
  so that path isn't bindable from here. Prefer `flatpak install --user`
  (exports under `~/.local/share/flatpak`, already visible via `$HOME`).
- **First-toggle cost:** the server pays the FUSE/namespace setup once at
  session start; each `toggle` pays a fresh (small, lean-image) setup. If that
  ever needs to be lower, a persistent-mount fast path in shellbox is the
  lever — not a box-side change.

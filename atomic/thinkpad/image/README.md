# image/ — custom Silverblue ("bluefin-style") image

A thin custom OCI image layered over stock Fedora Silverblue, built and
switched **entirely locally** — no registry, no GitHub Actions. Same model
Bluefin/Bazzite/finpilot use (a `Containerfile` derived from the official
Silverblue base), just kept intentionally minimal — we explicitly *don't* want
finpilot's multi-stage / common / brew / Justfile / CI machinery.

## What it changes

A few things on top of stock Silverblue, per the "keep the base minimal" rule in
the top-level README:

- **Remove `toolbox`, add `distrobox`.** distrobox provides the `distrobox` CLI
  on the host for ad-hoc containers, replacing `toolbox`. (The bespoke dev
  container in `../toolbox/` is unaffected — that one stays a plain
  `podman create` with a separate `$HOME`.)
- **Add `niri` (latest, via the `yalter/niri` COPR).** The `niri` package drops
  a `wayland-sessions/niri.desktop`, so GDM offers a "Niri" session alongside
  GNOME at the login gear menu — no GDM config needed. See the NOTE in the
  Containerfile about companion apps (waybar/fuzzel/alacritty) if you want a
  fully usable Niri session.
- **Add Noctalia v5 as a host binary, run via bubblewrap.** Noctalia needs
  native host session integration (Wayland, niri IPC, logind, `/sys` backlight
  notifications). The wrapper `noctalia-bwrap` keeps mutable XDG state isolated
  in a single plain-directory volume root, while avoiding the sysfs/inotify
  breakage seen in a full Podman container.
- **Add Vicinae as a host binary, run via bubblewrap.** Vicinae's real need in
  this repo is also native host session integration plus *state containment*,
  not container namespaces. The wrapper `vicinae-bwrap` keeps Vicinae's mutable
  XDG state isolated in the same plain-directory style as Noctalia while
  preserving native-fast `vicinae toggle` IPC from niri.

Everything else is stock.

## bootc, not rpm-ostree (the direction this is heading)

This image uses the **modern bootc-native build model**, matching current
Bluefin/finpilot. Concretely:

| Step | Old (rpm-ostree) | This image (bootc) |
|------|------------------|--------------------|
| Build-time packages | `rpm-ostree install` | `dnf5 install` |
| Remove a base package | `rpm-ostree override remove` | `dnf5 remove` |
| Finalize build | `ostree container commit` | `bootc container lint` |
| Deploy | `rpm-ostree rebase ostree-unverified-image:...` | `bootc switch --transport containers-storage ...` |
| Status | `rpm-ostree status` | `bootc status` |
| Rollback | `rpm-ostree rollback` | `bootc rollback` |

bootc is the stable, future-facing front-end. It still uses ostree/libostree
under the hood — per `bootc-status(8)`, "bootc and rpm-ostree share the same
code and do effectively the same thing" — but `bootc` is the blessed CLI going
forward and `dnf5` is the blessed build-time package manager.

## Layout

```
image/
├── Containerfile        # FROM silverblue:44 + distrobox + niri + Noctalia/Vicinae bwrap + bootc lint
├── noctalia-bwrap       # host-session Noctalia wrapper with isolated XDG state
├── vicinae-bwrap        # host-session Vicinae wrapper with isolated XDG state
├── vicinae-host-launch  # launch-prefix bridge: escape Vicinae app launches back to host
├── vicinae-settings.json # seeded Vicinae config (launch prefix, theme/font defaults)
├── build.sh             # sudo podman build  (root, so bootc can read it via containers-storage)
├── switch.sh            # ONE-TIME: bootc switch --transport containers-storage <local image>
├── upgrade.sh           # ROUTINE:  bootc upgrade  (apply a rebuilt :44)
├── rollback.sh          # bootc rollback  (atomic undo — no rebuild needed)
├── status.sh            # bootc status + local podman images
└── setup.sh             # one-shot first-time: build.sh then switch.sh
```

## Lifecycle

```bash
cd image/

# First time ONLY — adopt the custom image as the boot image:
./setup.sh              # build + bootc switch
systemctl reboot        # boot into the new deployment

# After that, for every Containerfile change it's build + UPGRADE (not switch):
./build.sh && ./upgrade.sh   # then: systemctl reboot

# Individual steps:
./build.sh              # build the image only
./switch.sh             # bootc switch — ONLY for first adopt / different image
./upgrade.sh            # bootc upgrade  — the routine rebuild-apply command

# Check what's deployed / what's built:
./status.sh

# Undo a bad deployment (the previous tree is still on disk):
./rollback.sh
systemctl reboot
```

Every `bootc` verb also takes `--apply` to reboot automatically, e.g.
`sudo bootc upgrade --apply` or
`sudo bootc switch --apply --transport containers-storage localhost/...`.

## How it works

- **Build** (`build.sh`): `sudo podman build` of `localhost/silverblue-thinkpad:44`
  (plus an immutable per-build tag `…:44-<sha>-<ts>`). Must be root so the image
  lands in `/var/lib/containers/storage`, where `bootc switch --transport
  containers-storage` reads it. The Containerfile uses `dnf5` for package changes
  (cache-mounted for fast rebuilds) and ends with `bootc container lint`, which
  validates the image before you ever switch to it. Every build also stamps a
  unique `IMAGE_VERSION` (git SHA + timestamp) as an OCI label and `/usr` file —
  see *switch once, upgrade thereafter* below.
- **Switch — one time only** (`switch.sh`): `bootc switch --transport
  containers-storage localhost/silverblue-thinkpad:44`. Sets the host's boot
  image reference. Run this ONCE to adopt the custom image (or to later re-point
  at a different image/tag). `switch` compares the image REFERENCE
  (transport+name+tag), not the image content, so re-running it against the same
  `:44` you're already on is a no-op by design ("Image specification is
  unchanged").
- **Upgrade — routine rebuilds** (`upgrade.sh`): `bootc upgrade`. Re-resolves
  the current `:44` reference from local podman storage and compares the image's
  MANIFEST/CONFIG DIGEST against the booted image; because the build's unique
  label changed that digest, a rebuild is detected and staged. This is the
  command to run after every `./build.sh`. Stages the new deployment as default;
  reboot to activate.
- **Rollback** (`rollback.sh`): bootc always keeps the previous deployment.
  `bootc rollback` swaps the default; reboot to use it. This is the safety net
  that makes custom images low-risk: a broken image costs one reboot, not a
  reinstall. Note: `/etc` changes don't carry across a rollback (per
  `bootc-rollback(8)`).

## Noctalia via bwrap

Noctalia is installed into the host image, but should be launched as:

```bash
noctalia-bwrap
```

This keeps host session/hardware integration native while redirecting mutable
state to named, auditable "volumes". By default:

```text
~/.local/share/bwrap/noctalia/
├── xdg-config/  # mounted as $HOME/.config; XDG_CONFIG_HOME
├── xdg-state/   # mounted as $HOME/.local/state; XDG_STATE_HOME
├── xdg-data/    # mounted as $HOME/.local/share; XDG_DATA_HOME
└── xdg-cache/   # mounted as $HOME/.cache; XDG_CACHE_HOME
```

Inside the bubblewrap namespace, the real host `$HOME` is hidden behind an
ephemeral tmpfs home. The host root filesystem is visible read-only so Noctalia
can use host packages, fonts, desktop entries, Flatpak exports, etc. The only
persistent writable user state is the explicit XDG-root volume tree above.
Noctalia's files then live at the conventional app paths inside those roots,
e.g. `xdg-state/noctalia/settings.toml` on the host corresponds to
`$HOME/.local/state/noctalia/settings.toml` in the sandbox.

`~/Pictures/Wallpapers` is the only extra `$HOME` path exposed, and it is
readonly by default (`NOCTALIA_WALLPAPERS_DIR` can point elsewhere).

Override the state root if desired:

```bash
NOCTALIA_VOLUME_ROOT="$HOME/Backups/noctalia-state" noctalia-bwrap
```

This is intentionally **not** backed by Podman volume internals. Podman volumes
are owned by Podman's storage metadata and are best managed by Podman
export/import. The bwrap analogue is a plain directory tree under
`~/.local/share/bwrap/`: easy to audit, snapshot, back up, or delete.

Migrating from the old Podman volumes is a one-level copy into the matching XDG
roots:

```bash
src="$HOME/.local/share/containers/storage/volumes"
dst="$HOME/.local/share/bwrap/noctalia"

mkdir -p \
  "$dst/xdg-config/noctalia" \
  "$dst/xdg-state/noctalia" \
  "$dst/xdg-data/noctalia" \
  "$dst/xdg-cache/noctalia"

cp -a "$src/noctalia-config/_data/." "$dst/xdg-config/noctalia/" 2>/dev/null || true
cp -a "$src/noctalia-state/_data/."  "$dst/xdg-state/noctalia/"  2>/dev/null || true
cp -a "$src/noctalia-data/_data/."   "$dst/xdg-data/noctalia/"   2>/dev/null || true
cp -a "$src/noctalia-cache/_data/."  "$dst/xdg-cache/noctalia/"  2>/dev/null || true
```

If migrating from an earlier bwrap wrapper that used `config/`, `state/`,
`data/`, and `cache/` as XDG roots, rename them once:

```bash
root="$HOME/.local/share/bwrap/noctalia"
[ -d "$root/config" ] && mv "$root/config" "$root/xdg-config"
[ -d "$root/state"  ] && mv "$root/state"  "$root/xdg-state"
[ -d "$root/data"   ] && mv "$root/data"   "$root/xdg-data"
[ -d "$root/cache"  ] && mv "$root/cache"  "$root/xdg-cache"
```

Apps launched *by Noctalia* inherit the isolated HOME/XDG variables and mount
namespace; apps launched directly by niri/terminals outside Noctalia are
unaffected.

Recommended niri startup:

```kdl
spawn-at-startup "noctalia-bwrap"
spawn-at-startup "vicinae-bwrap"
```

Brightness keys can go back to native Noctalia IPC once launched this way:

```kdl
binds {
    XF86MonBrightnessUp   { spawn-sh "noctalia msg brightness-up"; }
    XF86MonBrightnessDown { spawn-sh "noctalia msg brightness-down"; }
}
```

## Vicinae via bwrap

Vicinae is now launched as a host binary through:

```bash
vicinae-bwrap
```

This uses the same isolation model as `noctalia-bwrap`:

```text
~/.local/share/bwrap/vicinae/
├── xdg-config/  # mounted as $HOME/.config; XDG_CONFIG_HOME
├── xdg-state/   # mounted as $HOME/.local/state; XDG_STATE_HOME
├── xdg-data/    # mounted as $HOME/.local/share; XDG_DATA_HOME
└── xdg-cache/   # mounted as $HOME/.cache; XDG_CACHE_HOME
```

The host root filesystem is visible read-only so Vicinae can use host packages,
Qt plugins, themes, fonts, system desktop entries, and Flatpak exports. The
real host `$HOME` is still hidden behind a tmpfs home, so Vicinae cannot spray
files into the live host XDG tree.

The only extra host-user paths re-exposed are the readonly app/icon/Flatpak
export roots Vicinae needs for discovery:

- `~/.local/share/applications`
- `~/.local/share/icons`
- `~/.local/share/flatpak` (mounted whole so export symlinks resolve)
- `/var/lib/flatpak/exports/share`
- the normal system `/usr/{,local}/share` trees already visible through `/`

App launches are escaped back to the immutable host through the baked-in
`vicinae-host-launch` wrapper, which calls `host-spawn` over the host session
D-Bus. In Vicinae config this is set as the applications provider's
`launchPrefix`, so launched apps use their **real host profiles/state**, not the
sandbox HOME.

The wrapper seeds a minimal Vicinae config on first run and migrates state from
older locations when present:

- old container home: `~/.local/share/vicinae-container/`
- old host custom themes: `~/.local/share/vicinae/themes/`

The old container settings file is copied to
`xdg-config/vicinae/legacy-container-settings.json` for reference, but not used
live because it bakes in container-only app paths.

Do **not** enable the package's shipped `vicinae.service` user unit for this
setup — that would start an uncontained host server. Use niri startup instead:

```kdl
spawn-at-startup "vicinae-bwrap"

binds {
    Mod+Space { spawn "vicinae" "toggle"; }
}
```

`vicinae toggle` is now the native host binary talking directly to the shared
IPC socket under `$XDG_RUNTIME_DIR`, so the hotkey path stays low-latency.

## Updating after a change

Edit `Containerfile`, `noctalia-bwrap`, `vicinae-bwrap`,
`vicinae-host-launch`, or `vicinae-settings.json`, then
`./build.sh && ./upgrade.sh && systemctl reboot`. Note this is **upgrade**, not
switch — see below. Because the image is rebuilt fresh each time, this is a
clean, reproducible cycle — no accumulating client-side `rpm-ostree install`
state to drift.

To pull newer Fedora updates into the base, `build.sh` uses `--pull=newer`, so
a rebuild picks up the latest 44.x base automatically.

### switch once, upgrade thereafter

There are two subtly different bootc verbs and using the wrong one is the
classic local-build gotcha:

- `bootc switch` compares the image **reference** (transport + name + tag). It's
  for *changing the reference*: adopting the image the first time, or pointing
  at a different image/tag.
- `bootc upgrade` compares the image **content** (its manifest/config digest).
  It's for *applying new content of the same reference*: re-resolving `:44`
  from local storage and deploying if the digest changed.

Because our workflow rebuilds the same `:44` tag and wants the new content
applied, the routine command is `bootc upgrade`, NOT `bootc switch`. Running
`switch` against a `:44` you're already booted on is a no-op by design — it
prints `Image specification is unchanged` and stages nothing, because the
reference string is identical even though the image content is new.

For `bootc upgrade` to actually detect a rebuild, the image's manifest/config
digest must change. A rebuild that hits podman's layer cache produces
otherwise byte-identical layers, so `build.sh` injects a unique `IMAGE_VERSION`
(git short SHA + UTC timestamp) as the `org.opencontainers.image.version` OCI
**label**. Labels live in the image *config*, which is part of the manifest
digest — so every build gets a genuinely different digest, and `bootc upgrade`
always detects and stages it. (It's also written to
`/usr/lib/silverblue-thinkpad-version` so you can `cat` it on the booted host
and see exactly which build you're on.) This is the only layer that changes per
build, so the expensive `dnf5` layers above it stay cached and rebuilds stay
fast. `bootc status` shows the `Version` label and the image digest.

**Summary of the loop:** `switch.sh` once (first adopt / different image), then
`./build.sh && ./upgrade.sh` for every subsequent change.

## Customizing further

Add `dnf5` layers to the Containerfile for anything that genuinely can't live
in a container or flatpak. Keep the base stock otherwise. See the commented
examples in `Containerfile` (plain install, and a COPR enable→install→disable
pattern). Avoid putting GUI apps or dev tools here — those belong in flatpaks
or the `../toolbox/` dev container.

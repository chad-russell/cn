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
- **Optional: a whole Niri session run inside bubblewrap.** `niri-bwrap` applies
  the same containment idea to the compositor *itself* — every writable path in
  the login session is confined to `~/.local/share/bwrap/niri-session`. It is
  installed as a SECOND GDM entry ("Niri (bubblewrap)") next to stock Niri, so
  you can A/B them from the login gear menu. Experimental — see
  [Niri session via bwrap](#niri-session-via-bwrap-experimental).
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
├── niri-bwrap           # EXPERIMENTAL: whole Niri session in a bwrap mount sandbox
├── niri-bwrap.desktop   # the matching GDM wayland-session entry ("Niri (bubblewrap)")
├── vicinae-bwrap        # host-session Vicinae wrapper with isolated XDG state
├── vicinae-host-launch  # launch-prefix bridge: escape Vicinae app launches back to host
├── vicinae-settings.json # seeded Vicinae config (launch prefix, theme/font defaults)
├── build.sh             # sudo podman build  (root, so bootc can read it via containers-storage)
├── switch.sh            # bootc switch  (one-time adopt: install Silverblue, then switch onto this image)
├── upgrade.sh           # ROUTINE:  bootc upgrade  (apply a rebuilt :44)
├── rollback.sh          # bootc rollback  (atomic undo — no rebuild needed)
├── status.sh            # bootc status + local podman images
└── setup.sh             # one-shot build + switch  (first-time adopt)
```

## Lifecycle

```bash
cd image/

# First time: install stock Fedora Silverblue normally (the Anaconda ISO —
# the "just worked" experience), boot it, then adopt THIS custom image:
./setup.sh              # = ./build.sh && ./switch.sh  (one-time adopt)
systemctl reboot        # boot into the custom image

# After that, for every Containerfile change it's build + UPGRADE (not install):
./build.sh && ./upgrade.sh   # then: systemctl reboot

# Individual steps:
./build.sh              # build the image only
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

## Niri session via bwrap (experimental)

This is the compositor-level analogue of the two wrappers above: instead of
sandboxing a desktop-shell client of an already-running niri, `niri-bwrap`
sandboxes **niri itself**. Everything the login session writes — niri's config,
noctalia/vicinae state, anything niri spawns directly — is confined to a single
volume root, so the usual per-login filesystem cruft (terminal histories,
browser caches, stray dotfiles, …) physically cannot land on the real host.

It is wired up as a **separate GDM session entry**, so at the login gear menu
you get both:

- **Niri** — stock, unchanged, reads `~/.config/niri`.
- **Niri (bubblewrap)** — the sandboxed entry, reads its config from the volume.

Pick the normal one any time the sandboxed one misbehaves; nothing else changes.

```text
~/.local/share/bwrap/niri-session/
├── xdg-config/  # mounted as $HOME/.config; XDG_CONFIG_HOME   (niri config here)
├── xdg-state/   # mounted as $HOME/.local/state; XDG_STATE_HOME
├── xdg-data/    # mounted as $HOME/.local/share; XDG_DATA_HOME
└── xdg-cache/   # mounted as $HOME/.cache; XDG_CACHE_HOME
```

Inside the bubblewrap mount namespace, the real host `$HOME` is hidden behind a
private tmpfs. The host root filesystem is visible read-only (packages, fonts,
desktop files). `/dev` is exposed read-write in full (DRM/KMS, GPU render node,
input devices, `/dev/tty` for VT switching) — a compositor needs real device
access, and the threat model here is filesystem-cruft containment, not privilege
reduction on a single-user laptop. `$XDG_RUNTIME_DIR` and `/run/dbus` are exposed
so the Wayland socket, PipeWire, the user/session bus, niri's IPC socket, and
logind all keep working exactly as on the stock session.

### Why logind/KMS/input survive the sandbox

`niri-bwrap` creates **only a mount namespace** — it deliberately does NOT pass
`--unshare-pid` / `--unshare-user` / `--unshare-cgroup`. niri's PID therefore
stays in the login session's cgroup, `sd_pid_get_session()` still resolves it,
and logind makes niri the session controller and hands it the DRM + input fds
over the system bus. No special Linux capabilities are needed in the process.
This is exactly why this is a bubblewrap mount sandbox and not a Podman container
(a full container breaks logind's seat/VT mediation — the failure mode noted for
Noctalia).

### Why it runs `niri`, not `niri-session`

The package's normal launcher, `niri-session`, starts niri indirectly through
`systemctl --user` — i.e. *outside* any bubblewrap namespace — which would
defeat the sandbox. So `niri-bwrap` execs the `niri` binary directly and just
sets the desktop env vars (`XDG_CURRENT_DESKTOP=niri`, etc.) that niri-session
would otherwise export. niri/Smithay does its own logind seat takeover, so it
runs fine bare.

Concretely, that also means the wrapper must **not** set `WAYLAND_DISPLAY` or
`DISPLAY` in the sandbox. niri auto-selects its backend from the environment,
and if either is set it tries to run *nested* (as a client of an existing
compositor) and panics at startup with
`WaylandError(Connection(NoCompositor))`, because there is no parent
compositor to connect to. The wrapper `--unsetenv`s both, so niri uses its
native DRM/libseat backend, creates the Wayland socket itself under
`$XDG_RUNTIME_DIR`, and exports `WAYLAND_DISPLAY` into the environment of the
children it spawns. (This is the one real difference from `noctalia-bwrap` /
`vicinae-bwrap`, which *do* set `WAYLAND_DISPLAY` because they are clients of
niri rather than niri itself.)

#### The launcher: env import + logging

Because niri is exec'd bare rather than through `niri-session`, the wrapper
itself owes the session two things `niri-session` would otherwise do. So bwrap
execs a tiny inline launcher (the `NIRI_BWRAP_LAUNCHER` heredoc in the script)
instead of `niri` directly. It:

1. starts niri with **all** of its stdout/stderr captured to
   `~/.local/share/bwrap/niri-session/session.log` (previous run rotated to
   `session.log.old`),
2. once niri has created `$XDG_RUNTIME_DIR/wayland-0`, publishes
   `WAYLAND_DISPLAY` (+ the desktop session vars) into **both** the systemd
   user manager (`systemctl --user import-environment`) **and** the D-Bus
   activation environment (`dbus-update-activation-environment --all`), and
3. forwards SIGTERM/SIGINT/SIGHUP onto niri (the launcher, not niri, is the
   process bwrap waits on) and propagates niri's exit status to GDM.

Step 2 is the fix for the otherwise-inevitable "some apps don't launch"
symptom: niri only exports `WAYLAND_DISPLAY` into its *own* children's
environment, so D-Bus-activated apps and `systemctl --user`-started units
(portals, many Flatpaks, portal-using apps, some terminals) never see the
compositor until something advertises it on the user bus. The launcher imports
**only** the compositor-discovery vars — deliberately **not** `XDG_*_HOME`,
which would pollute the shared user manager (it runs *outside* the sandbox)
and make user services resolve state against the wrong tree. `dbus-x11` is
installed in the image specifically to provide `dbus-update-activation-environment`.

### Nested per-app wrappers keep persisting

A subtlety: if your niri config still does `spawn-at-startup "noctalia-bwrap"`
/ `"vicinae-bwrap"`, those become **nested** bubblewrap invocations inside the
session sandbox. On their own, their default volume root
(`$HOME/.local/share/bwrap/...`) would land on the session's tmpfs home and lose
persistence on logout. To prevent that, `niri-bwrap` re-binds the real host
`~/.local/share/bwrap` into the sandbox at the *same* path, so the nested
wrappers resolve their own volume roots to the real on-disk location and keep
behaving exactly as they do on the stock session. No config change needed.

### First-run config seeding

On first launch, if you already have a stock `~/.config/niri`, `niri-bwrap`
copies it into `xdg-config/niri` so the sandboxed session doesn't start bare.
The copy is one-shot and never overwrites an existing volume config, so the two
entries can later diverge independently.

### What is NOT contained

This contains niri plus what it spawns *directly*. Two intentional escape
hatches remain (both are already part of this setup's design on the stock
session too):

- **Apps launched through `vicinae-host-launch` / `host-spawn`** escape back to
  the host on purpose, so they use their real host profiles/state.
- **systemd `--user` services** (xdg-desktop-portal, polkit, …) are started by
  the user manager that PAM launches *outside* the sandbox, so they run
  uncontained. They're generally well-behaved system services.

### Caveats / things to expect on the first try

- xdg-desktop-portal / D-Bus app discovery is handled by the inline launcher
  (see *The launcher* above): once niri creates its Wayland socket, it runs
  `systemctl --user import-environment` and `dbus-update-activation-environment
  --all`. If portal-based file pickers or D-Bus-activated apps still misbehave,
  check `~/.local/share/bwrap/niri-session/session.log` for the launcher's
  status lines — it logs a warning there if either tool is missing or fails
  (e.g. `dbus-update-activation-environment not found (install dbus-x11)`).
- niri's full stdout/stderr (panics, Smithay logs, spawn-at-startup child
  output) plus the launcher's own status lines go to
  `~/.local/share/bwrap/niri-session/session.log`, rotated to `session.log.old`
  each session. This is the first place to look when something doesn't start.
- niri's config for this entry lives at
  `~/.local/share/bwrap/niri-session/xdg-config/niri/config.kdl`, i.e. a
  **different file** than stock Niri's `~/.config/niri/config.kdl`. Edit the
  right one.

Override the state root if desired:

```bash
NIRI_BWRAP_VOLUME_ROOT="$HOME/Backups/niri-session-state" niri-bwrap
```

### Iterating on `niri-bwrap` without a rebuild

Rebuilding the image (`./build.sh && ./upgrade.sh && systemctl reboot`) for
every tweak to `niri-bwrap` is slow. Two facts make a no-rebuild loop possible:

- `/usr/local` is writable on Silverblue (it is `/var/usrlocal`), and
- `/usr/local/share` is in the default `XDG_DATA_DIRS`, so GDM scans
  `/usr/local/share/wayland-sessions/` for session entries.

So a **separate** dev session entry dropped there takes effect on the next
login, with no reboot. The repo ships `niri-bwrap-dev.desktop` for exactly
this — it is intentionally NOT installed by the Containerfile (it is a
host-local dev convenience, kept out of the image). Its `Exec` points at a
stable name `/usr/local/bin/niri-bwrap-dev`, which you symlink once at your
repo checkout, so editing `image/niri-bwrap` → log out → log back in is a full
test cycle.

One-time setup (on the laptop):

```bash
cd /path/to/repo            # wherever atomic/thinkpad is checked out

# 1. Point a stable name at the repo's working-tree script. Re-run only if you
#    move/re-clone the checkout; nothing else needs to change.
sudo ln -sf "$PWD/image/niri-bwrap" /usr/local/bin/niri-bwrap-dev
chmod +x image/niri-bwrap                       # target must be executable

# 2. Install the dev session entry into the writable path GDM scans.
sudo install -d /usr/local/share/wayland-sessions
sudo install -m 0644 image/niri-bwrap-dev.desktop \
     /usr/local/share/wayland-sessions/niri-bwrap-dev.desktop
```

Log out and the GDM gear menu lists **Niri (bubblewrap, dev)** next to the
image-shipped **Niri (bubblewrap)**. The dev entry runs whatever bytes are at
`image/niri-bwrap` *right now*, so the loop is:

```bash
$EDITOR image/niri-bwrap          # tweak
# GDM: log out → pick "Niri (bubblewrap, dev)" → reproduce
tail -n 200 ~/.local/share/bwrap/niri-session/session.log
```

When the script is good, bake it with the normal
`./build.sh && ./upgrade.sh && systemctl reboot`; the dev entry keeps working
afterward because it points at the repo, not `/usr/bin`.

> **Do not test by switching to a VT** (e.g. VT3) and running `niri-bwrap`
> manually. A raw VT login gives niri a `tty` logind session, not a `wayland`
> one: `graphical-session.target` never starts, nothing publishes
> `WAYLAND_DISPLAY` to the session/D-Bus environment, and most apps refuse to
> launch. The failures you hit there are a *different* bug class than the
> GDM-session behavior you are fixing — always iterate through GDM.

## Updating after a change

Edit `Containerfile`, `noctalia-bwrap`, `niri-bwrap`, `niri-bwrap.desktop`,
`vicinae-bwrap`, `vicinae-host-launch`, or `vicinae-settings.json`, then
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

**Summary of the loop:** `./setup.sh` once to adopt (build + `bootc switch` onto
an installed Silverblue), then `./build.sh && ./upgrade.sh` for every subsequent
change.

## Customizing further

Add `dnf5` layers to the Containerfile for anything that genuinely can't live
in a container or flatpak. Keep the base stock otherwise. See the commented
examples in `Containerfile` (plain install, and a COPR enable→install→disable
pattern). Avoid putting GUI apps or dev tools here — those belong in flatpaks
or the `../toolbox/` dev container.

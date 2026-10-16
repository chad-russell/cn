# Hyprland round 2 — layered exploration kit

Everything needed to trial Hyprland on `think` **without image rebuilds**: a
one-time `rpm-ostree` layer, then all iteration happens in `~/.config` where
the compositor config hot-reloads and quickshell shells swap in ~1s. Only the
winner ever gets baked back into `host-image/`.

History: round 1 (2026-09-01 → 09-02) was image-baked via the
`mineiro/hyprland` COPR and retired in a day; the removal notes live in
`host-image/Containerfile` step 2 and `bubblebox/profile.toml`. Round 2 exists
because the things that were missing then are core Hyprland now: a
[scrolling layout][wiki-scrolling], a [monocle layout][wiki-monocle],
[per-workspace layouts via workspace rules][wiki-wsrules] (e.g.
`hl.workspace_rule({ workspace = "2", layout = "scrolling" })`), and layouts
are user-programmable in Lua (`hl.layout.register`, see upstream's
[example/layouts][hl-layouts]).

[wiki-scrolling]: https://wiki.hypr.land/configuring/layouts/scrolling-layout/
[wiki-monocle]: https://wiki.hypr.land/configuring/layouts/monocle-layout/
[wiki-wsrules]: https://wiki.hypr.land/configuring/core/rules/workspace-rules/
[hl-layouts]: https://github.com/hyprwm/Hyprland/tree/main/example/layouts

## Live facts (verified 2026-11, on-host)

- Fedora 44 repos have **no `hyprland` package at all** (`dnf5 info hyprland`
  → No matches). A COPR is mandatory.
- The [`mineiro/hyprland`][copr-mineiro] COPR (round 1's source) carries the
  whole suite: `hyprland hyprlock hypridle hyprpaper hyprpolkitagent
  hyprpicker hyprsunset uwsm xdg-desktop-portal-hyprland hyprland-qt-support
  hyprland-plugins` plus the Caelestia ecosystem (`caelestia-cli`,
  `dart-sass`, `hellwal`, fonts). [`solopasha/hyprland`][copr-solopasha] is
  the fuller alternative (adds astal/`hyprpanel`, `hyprland-git`, `pyprland`).
- The image already ships everything the shells need: quickshell 0.3.2
  (`errornointernet` COPR), Qt6 + fonts + matugen + portals, **and the full
  build toolchain** (`cmake ninja-build gcc-c++` + qt6-devel — Containerfile
  step 2.5 keeps it on purpose), so `hyprpm` plugin builds work on-host.
- Sessions on disk today: `gnome`, `gnome-classic`, `niri`. GDM shows new
  wayland-sessions automatically; no DM config needed.
- The same `errornointernet` COPR also ships `quickshell-git` — relevant if
  trying upstream Caelestia (below).

[copr-mineiro]: https://copr.fedorainfracloud.org/coprs/mineiro/hyprland/
[copr-solopasha]: https://copr.fedorainfracloud.org/coprs/solopasha/hyprland/

## Phase 1 — layer once, reboot once

```bash
sudo dnf5 copr enable mineiro/hyprland   # writes the COPR repo file under /etc/yum.repos.d
sudo rpm-ostree install hyprland hyprlock hypridle hyprpaper hyprpolkitagent
systemctl reboot
```

(rpm-ostree 2026.3 — what F44 ships — has **no** `--from-latest-copr`; the
enable-then-layer path above is the working one, verified on-host 2026-11.
`dnf5-plugins` is already installed on think. If `dnf5 copr enable` ever
refuses on an atomic host, fall back to dropping the repo file from
https://copr.fedorainfracloud.org/coprs/mineiro/hyprland/ into
`/etc/yum.repos.d/` by hand.)

Pick "Hyprland" at the GDM session gear. Layered packages ride on top of the
image deployment and survive `bootc upgrade` (the daily staging timer keeps
working); `rpm-ostree status` shows the layer.

Laptop sanity: add a hypridle config (`~/.config/hypr/hypridle.conf`) that
locks with hyprlock and suspends — during a short trial it's fine to skip.

## Phase 2 — the iterate loop (zero rebuilds)

1. `mkdir -p ~/.config/hypr && cp hosts/thinkpad/hyprland/hyprland.lua ~/.config/hypr/`
   — it implements the model (float-everything rule, ws3 scrolling, ws4
   monocle) and hot-reloads on every save.
2. Shells are just directories: `~/.config/quickshell/<name>`, started with
   `qs -c <name>`. Install several side by side; swap with
   `pkill -f "qs -c"; qs -c other &`.
3. Rescue from bee if a session wedges (hyprctl needs the instance env):

   ```bash
   ssh -o IdentitiesOnly=yes crussell@10.10.0.10 \
     'export XDG_RUNTIME_DIR=/run/user/$(id -u); export HYPRLAND_INSTANCE_SIGNATURE=$(ls $XDG_RUNTIME_DIR/hypr | head -1); hyprctl dispatch exit'
   ```

4. Plugins: `hyprpm add KZDKM/Hyprspace && hyprpm enable Hyprspace` builds
   on-host (toolchain is in the image). Re-run `hyprpm update` after every
   Hyprland version bump.

## The overview (pick one)

- [Hyprspace][hyprspace] — compositor-level animated workspace overview
  (GNOME/Plasma-style), works with any shell. Toggle dispatcher:
  `hyprctl dispatch overviewtoggle` (bind included as a comment in
  `hyprland.lua`).
- [quickshell-overview][qso] — standalone quickshell module: all workspaces,
  live window previews, drag-and-drop, Super+Tab. Drops into any minimal
  setup; pairs well with a light bar instead of a full dots repo.
- end-4's illogical-impulse ships its own overview (below).

[hyprspace]: https://github.com/KZDKM/Hyprspace
[qso]: https://github.com/Shanu-Kumawat/quickshell-overview

## Quickshell tasting menu

| env | flavor | Fedora reality |
|---|---|---|
| [end-4 / illogical-impulse][end4] | maximalist GNOME-like: overview, dock, AI widgets, animated everything | [Fedora port][end4fed] exists but its installer is dnf-based, "Fedora Workstation only" (tested F42, f42 branch) — layer its dependency list via rpm-ostree, then clone the config tree; own overrides go in `~/.config/hypr/custom` which survives updates |
| [Caelestia][caelestia] upstream | the shell our niri fork descends from — fluid morphing, dashboard | requires **quickshell-git** (image has 0.3.2 release); `quickshell-git` is in the errornointernet COPR — layering it over the baked quickshell needs an override/replace. Manual install = clone to `~/.config/quickshell/caelestia` + cmake, same `INSTALL_QSCONFDIR` flow as the fork |
| minimal bar + quickshell-overview | closest to how niri runs today | quickshell + matugen already in image; just clone the module |
| [Ax-Shell][axshell] | the other well-known quickshell shell (credited by Caelestia) | untested here |

[end4]: https://github.com/end-4/dots-hyprland
[end4fed]: https://github.com/EisregenHaha/fedora-hyprland
[caelestia]: https://github.com/caelestia-dots/shell
[axshell]: https://github.com/Axenide/Ax-Shell

Shell lifecycle: during the trial, start the shell from `hyprland.lua`
(`hl.on("hyprland.start", ...)`). `hyprland-shell@.service` in this dir is
the systemd version for the uwsm-managed session (template unit,
`systemctl --user enable --now hyprland-shell@<name>`); see its header for
why it needs uwsm.

## Revert

```bash
rpm-ostree uninstall hyprland hyprlock hypridle hyprpaper hyprpolkitagent
systemctl reboot          # or just boot the pre-layer deployment from GRUB
rm -rf ~/.config/hypr     # and any tasting shells under ~/.config/quickshell/
```

## Endgame — if Hyprland survives the trial

One image rebuild, one bubblebox change, both familiar:

1. `host-image/Containerfile` step 2: re-enable the COPR and install the
   keeper set (this is exactly what the round-1 removal comments describe):
   `dnf5 -y copr enable mineiro/hyprland` +
   `dnf5 -y install hyprland hyprlock hypridle hyprpaper hyprpolkitagent`
   (+ the chosen shell's extra deps), then drop the rpm-ostree layer.
2. **The build gate will reject the image until it is updated**: the shared
   verify script (`hosts/bees/thinkpad-image-verify.sh`, used by BOTH the
   nightly build and the CI `thinkpad-image` PR job) deliberately fails if
   `hyprland.desktop` is present — it was erected after round 1 to enforce
   the niri-only image. Baking Hyprland means flipping that check to assert
   the Hyprland session instead of rejecting it, in the same PR.
3. `bubblebox/profile.toml` `[[files]]`: declare `.config/hypr` (a dir entry,
   like `.config/nvim`) and any shell config that should be repo-tracked.
4. Move `hyprland-shell@.service` into `bubblebox/units/` (modeled on
   `caelestia-shell.service`, but `WantedBy=hyprland.service`) if running
   the uwsm session.
5. `thinkpad-image-health` asserts the niri session/shell artifacts — it
   stays green while niri remains in the image; extend its checks only if
   Hyprland becomes the primary.

Until then nothing here touches the image: this directory is staging only.

## Aside — MangoWM in the same loop

[MangoWM][mango] (dwl-based, 2026) implements this trial's whole wish list
natively — **per-tag layouts** (scroller, monocle, grid, deck, master-stack,
dwindle), a **built-in Hycov-style overview**, animations + scenefx effects,
hot-reload TOML config with `[[rules]]`/`exec-once`, IPC. It's young (one
main dev, small community) and the polished quickshell envs do NOT target
it — bars are bring-your-own (waybar / generic quickshell). On Fedora it
lives in the [Terra][terra] repo (not a COPR): same pattern — get Terra's
repo file into `/etc/yum.repos.d/`, then `rpm-ostree install mangowm`. It
makes a cheap second GDM session in this same exploration loop
(`~/.config/mango/` doesn't collide with `~/.config/hypr/`): A/B the *WM
model* on mango while the Hyprland trial A/B-s the *shell ecosystem*.

[mango]: https://github.com/mangowm/mango
[terra]: https://terrapkg.com/

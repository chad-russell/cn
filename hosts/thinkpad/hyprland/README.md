# Compositor trial (Hyprland + MangoWM) — declarative, image-based kit

Trial both compositors on `think`, fully declarative through this repo: the
host image carries the sessions, `~/.config` carries the behavior. Nothing
is layered or mutated on the live host.

2026-11 pivot: the rpm-ostree-layered start burned an evening (a zsh
inline-comment paste corrupted rpm-ostree args; Terra ships a chicken-and-egg
rpm pair — `terra-gpg-keys` only exists inside the repo `terra-release`
enables; and rpm-ostree finally aborted the whole transaction with
"SELinux enabled, but no policy found" on this SELINUX=disabled host —
nothing ever staged, but nothing ever worked either). The image path is the
house-philosophy one anyway, and its CI gate builds + verifies the image on
every PR, so no one debugs pastes at the laptop.

Round-1 history: the 2026-09-01 → 09-02 image-baked trial and its removal
notes live in `host-image/Containerfile` step 2 and
`bubblebox/profile.toml`.

## What's where

- **Image (PR-gated)**: `host-image/Containerfile` step 2 installs the
  hyprland suite + waybar from the `mineiro/hyprland` COPR; step 2.7 installs
  `mangowm` from Terra (the gpg-keys + release rpm pair, pinned URLs — no
  published `terra.repo` exists). `hosts/bees/thinkpad-image-verify.sh`
  gate 2 asserts **niri + hyprland + mango** sessions in every build.
  The CI `thinkpad-image` job builds the full image and runs those gates on
  every PR — merge only on green (verified working: CI run #349, 2026-11).
- **Configs (this dir)**: `hyprland.lua` and `mango-snippet.conf` implement
  the trial model in each compositor — float by default, workspace/tag 3
  scrolling, 4 monocle, animated overview.

## Install (all agent-driven except the merge + reboot)

1. Merge the bake PR (hyprland + mangowm in the image) and this runbook PR.
2. Agent triggers the bees build and stages it on think via the daily user
   unit (`thinkpad-image-update.service`, passwordless `bootc upgrade`).
   The 05:10 nightly would also do it unattended.
3. **Reboot.** GDM gear gains Hyprland and Mango next to niri/GNOME.
4. One-time cleanup of the abandoned layered start (nothing was staged;
   this only drops the COPR repo file and the downloaded rpm cache):

   ```bash
   sudo dnf5 copr disable mineiro/hyprland
   sudo rpm-ostree cleanup -b -m
   ```

   (Flags verified against `rpm-ostree cleanup --help` on think 2026-11:
   `-b` clears temporary/pkg files, `-m` the cached rpm-md metadata. There
   is no `--pkg-cache` option in rpm-ostree 2026.3. Purely cosmetic — ~72 MB.)

## Stage the configs

The Hyprland config is a bubblebox `[[files]]` entry — it lives at
`bubblebox/files/.config/hypr/hyprland.lua` in this repo and deploys as a
symlink (same model as niri's config.kdl):

```bash
cjust bubblebox-apply
```

After that, editing `~/.config/hypr/hyprland.lua` edits the repo checkout
directly; commit from think is the only remaining step. (The mango snippet
below is dormant since mango left the image.)

## The iterate loop (zero rebuilds)

1. Both configs hot-reload on save — Hyprland's `hyprland.lua` (the `hl.*`
   Lua API) and mango's `config.conf`. No reboot for config, ever.
2. Shells are just directories: `~/.config/quickshell/<name>`, started with
   `qs -c <name>`. Install several side by side; swap with
   `pkill -f "qs -c"; qs -c other &`.
3. Rescue from bee if a session wedges (hyprctl needs the instance env):

   ```bash
   ssh -o IdentitiesOnly=yes crussell@10.10.0.10 \
     'export XDG_RUNTIME_DIR=/run/user/$(id -u); export HYPRLAND_INSTANCE_SIGNATURE=$(ls $XDG_RUNTIME_DIR/hypr | head -1); hyprctl dispatch exit'
   ```

   (mango: `loginctl terminate-session` from the same SSH.)
4. Plugins: `hyprpm add KZDKM/Hyprspace && hyprpm enable Hyprspace` builds
   on-host (toolchain is in the image). Re-run `hyprpm update` after every
   Hyprland version bump.

Package-level changes DO mean an image PR — that's the deal now, and it's
fine: the trial's package set is fixed (both compositors ship in the image);
everything else is config.

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

| env | flavor | notes |
|---|---|---|
| [end-4 / illogical-impulse][end4] | maximalist GNOME-like: overview, dock, AI widgets | config tree is cloneable; image already carries most deps (kdialog, kirigami, matugen…) |
| [Caelestia][caelestia] upstream | the shell our niri fork descends from | requires **quickshell-git** (image has 0.3.2) — if tasted, that's an image PR (add `quickshell-git` from the errornointernet COPR, replacing the release build) |
| minimal bar + quickshell-overview | closest to how niri runs today | quickshell + matugen already in image; just clone the module |
| [Ax-Shell][axshell] | the other well-known quickshell shell | untested here |

[end4]: https://github.com/end-4/dots-hyprland
[caelestia]: https://github.com/caelestia-dots/shell
[axshell]: https://github.com/Axenide/Ax-Shell

Shell lifecycle: the desktop shell under Hyprland and mango is **Ambxst**
(same binary + sources as niri). Under Hyprland it starts from
`hyprland.lua` (`hl.on("hyprland.start", ...)`); under mango, ambxst's own
axctl startup integration starts it (`exec-once = ambxst`, generated into
`~/.local/share/ambxst/mango.conf` and `source`d by our mango config). The
launcher is vicinae: `vicinae.service` (graphical-session.target) runs under
every compositor; Mod+Space toggles it in niri, Hyprland and mango.
`hyprland-shell@.service` in this dir is the generic template for running
any quickshell config under the uwsm session; see its header for why it
needs uwsm.

Session-entry map (GDM → what actually runs):

- `niri.desktop` → niri (image).
- `hyprland-uwsm.desktop` → `uwsm start -e -D Hyprland hyprland.desktop`
  (image; Name= "Hyprland" since the 2026-10 rename — the stock
  "(uwsm-managed)" suffix is cosmetic noise). The `hyprland.desktop` in
  that Exec line resolves **user-scope** via the XDG data hierarchy:
  `~/.local/share/wayland-sessions/hyprland.desktop`, a bubblebox
  `[[files]]` entry. The image deliberately ships no system copy (GDM
  would list it as a second entry) — but a missing user-scope copy breaks
  every Hyprland login ("uwsm: Could not find entry" → GDM bounce), which
  is exactly the 2026-10 crash; the bubblebox file is the fix.
- `mango.desktop` → mango directly (image, Terra). No uwsm under mango —
  the mango config imports the Wayland env into the user manager itself
  (`dbus-update-activation-environment`).

## MangoWM session (the B half of the A/B)

The image installs `mangowm` (deps incl. scenefx come along). Starter
config = stock default + the trial snippet (float everywhere via
`tag_rule=id:*,open_as_floating:1`, tag 3 scroller, tag 4 monocle, Super+Tab
overview, waybar + ghostty) — see "Stage the configs" above.

What to actually try (the things Hyprland can't give you natively):

- **Tags, not workspaces** — view multiple tags at once (Ctrl+<num> adds).
  Give it a full evening before judging; it inverts the workspace mental
  model. `no_hide` keeps tags 3/4 alive.
- **Per-tag layouts** — every tag remembers its own layout; Super+N cycles
  scroller → monocle → tile; assign defaults per tag in the snippet.
- **Built-in overview** — Super+Tab, live window previews across all tags,
  jump labels, click-to-focus / right-click-to-close. No plugin needed.
- **mmsg IPC** — `mmsg` is mango's hyprctl; window/tag state for waybar.

Caveats: young project (one main dev, Discord-sized community), and **no
quickshell envs target it** — bars are bring-your-own (waybar here). If the
thing you end up loving is a shell (Caelestia / end-4), that's a Hyprland
answer by definition. Docs: https://mangowm.github.io/docs

## Revert (declarative)

- Remove the trial blocks (Containerfile step 2's hyprland lines + step 2.7
  + the gate's hyprland/mango assertions) in a PR; `cjust image-upgrade` +
  reboot drops the sessions. niri was never touched.
- `rm -rf ~/.config/hypr ~/.config/mango` (plus any tasting shells under
  `~/.config/quickshell/`).

## Endgame — when the trial has a keeper

1. Delete the loser's Containerfile block + verify-gate line (one PR).
2. Move the winning config into bubblebox: `[[files]]` entry for
   `.config/hypr` (dir entry, like `.config/nvim`) or `.config/mango`.
3. `hyprland-shell@.service` → `bubblebox/units/` (modeled on
   `caelestia-shell.service`, but `WantedBy=hyprland.service`) if running
   the uwsm session.
4. `thinkpad-image-health` stays green while niri remains in the image;
   extend its checks only if Hyprland/Mango becomes the primary.

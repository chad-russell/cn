-- Hyprland round-2 exploration skeleton for `think`.
--
-- Install:  mkdir -p ~/.config/hypr && cp hyprland.lua ~/.config/hypr/
-- Hyprland reads ~/.config/hypr/hyprland.lua (Lua config, the `hl.*` API)
-- and hot-reloads on save. Classic hyprland.conf still works too — the
-- current upstream example config is this Lua form, and the wiki documents
-- the new features (scrolling/monocle layouts, per-workspace layouts) in it.
--
-- Syntax verified against hyprwm/Hyprland example/hyprland.lua @ main and
-- the wiki code-snippets page (2026-11). The layout model this skeleton
-- implements is the point of the trial — see ./README.md:
--   * floating by default (one window rule)
--   * workspace 3 = scrolling tape (niri/PaperWM feel), workspace 4 = monocle
--   * animated overview via the Hyprspace plugin or quickshell-overview

-- ghostty is a bubblebox tool: the wrapper lives at ~/.local/bin/ghostty.
-- Use the explicit $HOME path — GDM launches Hyprland with a thin session
-- env whose PATH may not include ~/.local/bin ($HOME expands because
-- exec_cmd runs through a shell; see upstream's example binds).
local terminal = "$HOME/.local/bin/ghostty"

-- ── monitors ──────────────────────────────────────────────────────────────
-- eDP-1 explicit: scale "auto" computed 1.5 on this 1920x1200 14" panel and
-- everything rendered huge; niri runs it at 1.0 (bubblebox niri config.kdl)
-- — match that.
hl.monitor({ output = "eDP-1", mode = "1920x1200@60", position = "0x0", scale = "1.0" })
-- Docked — mirror niri's config.kdl entries when needed (names via
-- `hyprctl monitors`; the Dell shows up as DP-*):
-- hl.monitor({ output = "DP-1", mode = "2560x1440@59.951", position = "auto", scale = "1.0" })

hl.env("XCURSOR_SIZE", "24")
-- hl.env("XCURSOR_THEME", "Bibata-...") -- bibata-cursor-themes is in the
-- image; match the theme string niri uses before uncommenting.

-- ── input ─────────────────────────────────────────────────────────────────
hl.config({
    input = {
        kb_options = "caps:swapescape", -- same as niri + GNOME (dconf layer)
        follow_mouse = 0,
        -- Keyboard focus (Alt+Tab) must be allowed to leave the hovered
        -- window. With this on, Hyprland's raise path snaps focus back to
        -- whatever is under the cursor.
        mouse_refocus = false,
        touchpad = {
            natural_scroll = true, -- trackpad direction like GNOME/niri
        },
    },
})

-- Hyprspace overview styling/behavior. NOTE: plugin config keys only exist
-- once the plugin is loaded — UNCOMMENT this block after running
-- `hyprpm enable Hyprspace`, else Hyprland errors on the unknown key
-- (verified live). All options in the Hyprspace README: dragAlpha,
-- showNewWorkspace, onBottom, reservedArea, exitKey, ...
-- hl.config({
--     plugin = {
--         overview = {
--             centerAligned = true, -- KDE/macOS-style centered strip
--         },
--     },
-- })

-- ── the trial's model: floating by default ────────────────────────────────
-- APPEARANCE PAIRING: Ambxst/axctl applies look changes as LIVE keywords
-- from ~/.local/share/ambxst/axctl.toml and never persists them here —
-- every reload of this file re-asserts whatever is declared below. So the
-- geometry values here intentionally MIRROR axctl.toml (gaps 2/4, border 2,
-- rounding 16, blur on). Change appearance in the Ambxst UI for a live
-- preview, then mirror the winner into this block (both sides must agree,
-- else you get the flash-then-revert effect). Border COLORS stay out of
-- here on purpose: axctl sets them from the live matugen palette.
hl.config({
    general = {
        gaps_in = 2,
        gaps_out = 4,
        border_size = 2,
        -- Fallback layout for the rare window you DO tile into a layout
        -- workspace (everything else floats via the rule below).
        layout = "dwindle",
    },
    decoration = {
        rounding = 16,
        blur = {
            enabled = true,
            size = 4,
            passes = 2,
        },
    },
    animations = { enabled = true },
})

-- Everything floats unless a later rule tiles it back in.
hl.window_rule({
    name = "float-by-default",
    match = { class = ".*" },
    float = true,
})
-- Tile specific apps into a layout workspace instead (example):
-- hl.window_rule({
--     name = "tile-ghostty-on-3",
--     match = { class = "^ghostty$" },
--     float = false,
--     workspace = "3",
-- })

-- ── per-workspace layouts (core Hyprland now — no plugins) ────────────────
-- Scrolling = infinitely growing tape. Monocle = one window full-bleed.
-- (Both are core; workspace rules assign them per workspace.)
hl.workspace_rule({ workspace = "3", layout = "scrolling" })
hl.workspace_rule({ workspace = "4", layout = "monocle" })

-- Scrolling options worth knowing (from upstream's example config):
hl.config({ scrolling = { fullscreen_on_one_column = true } })
-- Monocle cycling dispatcher: see the wiki Monocle Layout page for the
-- exact hl.dsp.layout(...) form and bind it if you adopt workspace 4.

-- Custom layouts are user-programmable in plain Lua — no C plugins. Upstream
-- ships examples (columns/grid/manual/spiral) using:
--   hl.layout.register("mylayout", { recalculate = function(ctx) ... end })
-- See https://github.com/hyprwm/Hyprland/tree/main/example/layouts

-- ── shell + overview ──────────────────────────────────────────────────────
hl.on("hyprland.start", function()
    -- Import the Wayland env into the systemd user manager: the bubblebox
    -- wrappers spawn GUI apps via `systemd-run --user`, and vicinae/portal
    -- children need WAYLAND_DISPLAY *and* DISPLAY (X11-defaulting Electron
    -- apps like Slack crash without DISPLAY even though XWayland is up —
    -- diagnosed live 2026-11). Without uwsm nothing else does this import.
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE DISPLAY")
    -- Start the session target FIRST: plain GDM-launched Hyprland never
    -- starts graphical-session.target (RefuseManualStart — only uwsm/desktop
    -- sessions may pull it), and xdg-desktop-portal.service has
    -- Requisite= on it — without this, NO portals run (diagnosed live
    -- 2026-11: every portal failure traced here). hyprland-session.target
    -- (this repo, deployed to ~/.config/systemd/user/) pulls it in.
    hl.exec_cmd("systemctl --user start hyprland-session.target")
    -- vicinae (launcher): bound to graphical-session.target upstream, but
    -- started directly too for determinism.
    hl.exec_cmd("systemctl --user start vicinae.service")
    -- Desktop shell: Ambxst (Axenide; Go binary supervising a quickshell
    -- shell + axctl + wl-paste). Deployed user-space: binary + axctl in
    -- ~/.local/bin (checksum-verified), sources at ~/.local/src/ambxst,
    -- pointer in ~/.local/share/ambxst/shell_repo, phosphor fonts installed.
    -- PATH export: the compositor session PATH lacks ~/.local/bin and the
    -- binary shells out to axctl. Swap shells by changing this one line.
    -- Logs: journalctl --user -u ambxst-trial (first run was transient).
    hl.exec_cmd("export PATH=$HOME/.local/bin:$PATH; exec $HOME/.local/bin/ambxst")
    -- Overview, compositor-level (needs `hyprpm add KZDKM/Hyprspace` first):
    -- hl.exec_cmd("hyprctl dispatch overviewtoggle")
end)
-- Alternative overview without a plugin: the standalone quickshell module
-- https://github.com/Shanu-Kumawat/quickshell-overview (live previews of all
-- workspaces, Super+Tab toggle) — run it as its own qs config alongside a bar.

-- ── binds ─────────────────────────────────────────────────────────────────
local mainMod = "SUPER"

hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))
-- App switching: Alt+Tab muscle memory. 0.56-native typed dispatchers
-- (string dispatch like cyclenext is gone; cycle_next({next=false}) = prev).
hl.bind("ALT + TAB", hl.dsp.window.cycle_next())
hl.bind("ALT + SHIFT + TAB", hl.dsp.window.cycle_next({ next = false }))
-- Overview: Hyprspace plugin (KZDKM) — compositor-level expo: live window
-- previews, drag windows between workspaces, touchpad swipe. Enabled with:
--   hyprpm add https://github.com/KZDKM/Hyprspace && hyprpm enable Hyprspace
-- (interactive sudo, run once in a terminal). The closure only touches the
-- plugin namespace on keypress, so this bind is safe even before enabling.
-- Same key as mango's built-in overview for A/B muscle-memory parity.
hl.bind(mainMod .. " + TAB", function()
    hl.plugin.overview.toggle()
end)
hl.bind(mainMod .. " + SHIFT + TAB", function()
    hl.plugin.overview.toggle("all")
end)
-- Launcher — same Mod+Space muscle memory as niri (vicinae daemon client).
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd("$HOME/.local/bin/vicinae toggle"))
hl.bind(mainMod .. " + C", hl.dsp.window.close())
-- niri parity: Mod+Q is the real close key (C kept as upstream's alias)
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
-- Screenshot, niri's Mod+P slot: slurp an area, copy PNG to clipboard.
-- (grim/slurp/wl-clipboard are baked in the image; Shift variant saves to
-- ~/Pictures/Screenshots like niri's default path.)
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd('grim -g "$(slurp)" - | wl-copy'))
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd('grim -g "$(slurp)" "$HOME/Pictures/Screenshots/$(date +%F-%H%M%S).png"'))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("hyprctl dispatch exit"))

-- Focus / workspaces
hl.bind(mainMod .. " + h", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + l", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + k", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + j", hl.dsp.focus({ direction = "down" }))

-- Any focus change raises that floating window, so Alt+Tab is visible.
local raising_focused = false
hl.on("window.active", function(w)
    if raising_focused or w == nil or not w.floating then
        return
    end
    raising_focused = true
    hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = w }))
    raising_focused = false
end)
-- Adjacent workspace on this monitor, including an empty one (r±1).
hl.bind(mainMod .. " + CTRL + h", hl.dsp.focus({ workspace = "r-1" }))
hl.bind(mainMod .. " + CTRL + l", hl.dsp.focus({ workspace = "r+1" }))
-- Move the focused window with you.
hl.bind(mainMod .. " + SHIFT + h", hl.dsp.window.move({ workspace = "r-1" }))
hl.bind(mainMod .. " + SHIFT + l", hl.dsp.window.move({ workspace = "r+1" }))

for i = 1, 10 do
    local key = i % 10 -- workspace 10 maps to key 0
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Scratchpad
hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Move/resize floating windows with Super + LMB/RMB drag
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Laptop media keys (wpctl + brightnessctl are both in the image)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

-- ── upstream's two near-universal window rules ────────────────────────────
-- Ignore maximize requests from apps (floating envs want this).
hl.window_rule({
    name = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})
-- Fix some dragging issues with XWayland windows.
hl.window_rule({
    name = "fix-xwayland-drags",
    match = {
        class = "^$",
        title = "^$",
        xwayland = true,
        float = true,
        fullscreen = false,
        pin = false,
    },
    no_focus = true,
})

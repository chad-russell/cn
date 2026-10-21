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

-- Ambxst
loadfile(os.getenv("HOME") .. "/.local/share/ambxst/hyprland.lua")()

-- Unbind Ambxst unwanted keybinds
hl.unbind("SUPER + Super_L")
hl.unbind("SUPER + L")

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
-- NOTE: this config assumes the uwsm-managed session (GDM entry "Hyprland")
-- → hyprland-uwsm.desktop). uwsm's launch target hyprland.desktop is a
-- USER-scope bubblebox file (~/.local/share/wayland-sessions/) — inside the
-- XDG data hierarchy so uwsm finds it, outside the system session dirs so
-- GDM never lists it (the image deletes the system copy, step 2.4). uwsm
-- handles everything
-- the plain session needed hand-rolled workarounds for: the dbus/systemd
-- env imports (incl. DISPLAY after XWayland starts) and
-- graphical-session.target startup (portals, vicinae binding). Those
-- workarounds were removed 2026-11 after verifying the uwsm session live.
hl.on("hyprland.start", function()
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
-- Overview: hymission, niri's Mod+O slot. Closures touch the plugin only on
-- keypress, so this file still loads if the plugin is disabled.
-- onlycurrentworkspace is the current workspace; Shift shows every workspace.
hl.bind(mainMod .. " + O", function()
    hl.plugin.hymission.toggle("onlycurrentworkspace")
end)
hl.bind(mainMod .. " + SHIFT + O", function()
    hl.plugin.hymission.toggle("forceall")
end)

-- Plugin styling keys only exist once the plugin is loaded (see the
-- Hyprspace note above — same failure mode, verified live 2026-11: this
-- block uncommented with no plugin installed broke every session start).
-- Re-enable together with the hymission binds above:
-- hl.config({
--     plugin = {
--         hymission = {
--             selected_expand_scale = 1.0,
--             hover_expand_scale = 1.25,
--             overview_focus_follows_mouse = 0,
--         }
--     }
-- })

-- Launcher — same Mod+Space muscle memory as niri (vicinae daemon client).
hl.unbind(mainMod .. " + SPACE")
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd("$HOME/.local/bin/vicinae toggle"))

-- niri parity: Mod+Q is the real close key (C kept as upstream's alias)
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + Q", hl.dsp.window.close())

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
hl.unbind(mainMod .. "+ CTRL + k")
hl.bind(mainMod .. " + CTRL + k", hl.dsp.focus({ workspace = "r-1" }))

hl.unbind(mainMod .. "+ CTRL + j")
hl.bind(mainMod .. " + CTRL + j", hl.dsp.focus({ workspace = "r+1" }))

-- Move the focused window with you.
hl.unbind(mainMod .. "+ SHIFT + k")
hl.bind(mainMod .. " + SHIFT + k", hl.dsp.window.move({ workspace = "r-1" }))

hl.unbind(mainMod .. "+ SHIFT + j")
hl.bind(mainMod .. " + SHIFT + j", hl.dsp.window.move({ workspace = "r+1" }))

for i = 1, 10 do
    local key = i % 10 -- workspace 10 maps to key 0
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Scratchpad
hl.bind(mainMod .. " + M", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.window.move({ workspace = "special:magic" }))

-- Move/resize floating windows with Super + LMB/RMB drag
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

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

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

local terminal = "ghostty" -- bubblebox tool; wrapper resolves on PATH

-- ── monitors ──────────────────────────────────────────────────────────────
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
-- External Dell P3225QE over USB-C: check `hyprctl monitors` for the output
-- name, then add e.g.:
-- hl.monitor({ output = "DP-1", mode = "preferred", position = "auto" })

hl.env("XCURSOR_SIZE", "24")
-- hl.env("XCURSOR_THEME", "Bibata-...") -- bibata-cursor-themes is in the
-- image; match the theme string niri uses before uncommenting.

-- ── the trial's model: floating by default ────────────────────────────────
hl.config({
    general = {
        gaps_in = 6,
        gaps_out = 10,
        border_size = 2,
        -- Fallback layout for the rare window you DO tile into a layout
        -- workspace (everything else floats via the rule below).
        layout = "dwindle",
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
    -- Pick ONE quickshell env per tasting session (see ./README.md). Kill the
    -- old one first: pkill -f "qs -c" (shells are just dirs under
    -- ~/.config/quickshell/<name>, run with `qs -c <name>`).
    hl.exec_cmd("qs -c REPLACE_ME") -- e.g. caelestia / illogical-impulse
    -- Overview, compositor-level (needs `hyprpm add KZDKM/Hyprspace` first):
    -- hl.exec_cmd("hyprctl dispatch overviewtoggle")
end)
-- Alternative overview without a plugin: the standalone quickshell module
-- https://github.com/Shanu-Kumawat/quickshell-overview (live previews of all
-- workspaces, Super+Tab toggle) — run it as its own qs config alongside a bar.

-- ── binds ─────────────────────────────────────────────────────────────────
local mainMod = "SUPER"

hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("hyprctl dispatch exit"))

-- Focus / workspaces
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))

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

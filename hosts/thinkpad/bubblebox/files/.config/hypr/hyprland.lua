-- Hyprland config — Caelestia trial (2026-09-01)
--
-- Lua format: hyprlang .conf support is REMOVED in Hyprland 0.57 (this
-- image ships 0.56), so the config is Lua from day one.
--
-- Bind philosophy: faithful niri-parity mapping (see
-- bubblebox/files/.config/niri/config.kdl binds{}) — focus HJKL/arrows,
-- move via Ctrl, workspace nav via Shift+J/K, monitor focus via
-- Shift+arrows — PLUS stock-Hyprland numeric workspaces (1-9) and
-- Mod+click-drag window management. The full Caelestia "dots" experience
-- (their managed Lua config with hypr-vars overrides) is the alternative —
-- if this trial graduates, `caelestia install` writes their tree instead.

local mainMod = "SUPER"

-- ---- monitors: niri parity (niri config.kdl outputs{}) --------------------
-- Home desk: laptop + two 4K Samsungs above (niri uses generic DP-3/DP-5
-- names for them — same boot-order tradeoff there). Work desk Dells are
-- matched by full description (distinct serials).
-- NOTE: position uses the "XxY" string form ("−3648x−1728"), per the wiki.
hl.monitor({ output = "eDP-1", mode = "1920x1200@60", position = "0x0", scale = 1 })
hl.monitor({ output = "DP-3", mode = "3840x2160@60", position = "-3648x-1728", scale = 1.25 })
hl.monitor({ output = "DP-5", mode = "3840x2160@60", position = "-576x-1728", scale = 1.25 })
hl.monitor({ output = "desc:Dell Inc. DELL P3225QE 616K784", mode = "2560x1440@59.951", position = "320x-1440", scale = 1 })
hl.monitor({ output = "desc:Dell Inc. DELL P3225QE 5KCK784", mode = "3840x2160@59.997", position = "-576x-1728", scale = 1.25 })

-- Cursor: set BOTH variable families. Hyprland renders its own cursor via
-- hyprcursor; leaving HYPRCURSOR_* unset makes it fall back to a default
-- theme/size and then multiply by monitor scale (the "too big cursor").
-- Rounded window corners (matches the shell border rounding so window and
-- shell overlay geometry agree). Officially supported decoration:rounding.
hl.config({
    decoration = {
        rounding = 16,
    },
})

hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Ice")
hl.env("HYPRCURSOR_SIZE", "24")

-- Match niri keyboard/touchpad behaviour:
--   xkb options "caps:swapescape"; touchpad tap + natural-scroll +
--   scroll-factor 0.22
hl.config({
    input = {
        kb_layout  = "us",
        kb_options = "caps:swapescape",

        touchpad = {
            natural_scroll = true,
            tap_to_click   = true,
            scroll_factor  = 0.22,
        },
    },
})

-- Fedora's start-hyprland wrapper does not bring up the systemd user
-- graphical session (niri/GNOME do this themselves). hyprland-session.target
-- is the canonical bridge: starting it dependency-starts
-- graphical-session.target (which refuses manual start), which pulls in
-- user units like the vicinae launcher daemon.
hl.on("hyprland.start", function()
    hl.exec_cmd("systemctl --user start hyprland-session.target")
    hl.exec_cmd("quickshell -c caelestia")
end)

-- ---- focus (niri: Mod+arrows / HJKL) --------------------------------------
local function focus(dir)
    return hl.dsp.focus({ direction = dir })
end
hl.bind(mainMod .. " + Left",  focus("left"))
hl.bind(mainMod .. " + Right", focus("right"))
hl.bind(mainMod .. " + Up",    focus("up"))
hl.bind(mainMod .. " + Down",  focus("down"))
hl.bind(mainMod .. " + H",     focus("left"))
hl.bind(mainMod .. " + L",     focus("right"))
hl.bind(mainMod .. " + K",     focus("up"))
hl.bind(mainMod .. " + J",     focus("down"))

-- ---- move window within layout (niri: Mod+Ctrl+Left/Right, Ctrl+H/L) ------
local function moveWin(dir)
    return hl.dsp.window.move({ direction = dir })
end
hl.bind(mainMod .. " + CTRL + Left",  moveWin("left"))
hl.bind(mainMod .. " + CTRL + Right", moveWin("right"))
hl.bind(mainMod .. " + CTRL + H",     moveWin("left"))
hl.bind(mainMod .. " + CTRL + L",     moveWin("right"))
-- niri: Mod+Ctrl+Up/Down + Ctrl+J/K = move window to prev/next workspace
hl.bind(mainMod .. " + CTRL + Up",   hl.dsp.window.move({ workspace = "e-1" }))
hl.bind(mainMod .. " + CTRL + Down", hl.dsp.window.move({ workspace = "e+1" }))
hl.bind(mainMod .. " + CTRL + K",    hl.dsp.window.move({ workspace = "e-1" }))
hl.bind(mainMod .. " + CTRL + J",    hl.dsp.window.move({ workspace = "e+1" }))

-- ---- workspace nav (niri: Mod+Shift+J/K) -----------------------------------
hl.bind(mainMod .. " + SHIFT + J", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + SHIFT + K", hl.dsp.focus({ workspace = "e-1" }))
-- numeric workspaces too (additive; niri has none)
for i = 1, 9 do
    hl.bind(mainMod .. " + " .. i, hl.dsp.focus({ workspace = i }))
end

-- ---- resize (niri: Mod+Minus/Equal width, +Shift height) --------------------
-- Caelestia upstream resize helper: percentage of the window's own size.
local function resize(pct_x, pct_y)
    return function()
        local win = hl.get_active_window()
        if win and win.size then
            hl.dispatch(hl.dsp.window.resize({
                x = win.size.x * (pct_x / 100),
                y = win.size.y * (pct_y / 100),
                relative = true,
            }))
        end
    end
end
hl.bind(mainMod .. " + minus",         resize(-10, 0))
hl.bind(mainMod .. " + equal",         resize(10, 0))
hl.bind(mainMod .. " + SHIFT + minus", resize(0, -10))
hl.bind(mainMod .. " + SHIFT + equal", resize(0, 10))

-- ---- window actions (niri parity) -------------------------------------------
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + V", hl.dsp.window.float())
hl.bind(mainMod .. " + X", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind(mainMod .. " + W", hl.dsp.group.toggle())
-- ---- screenshots (niri Mod+P parity): shell-side AreaPicker =========
-- click-drag region select. Freeze mode freezes the screen while picking.
-- (The CLI `caelestia screenshot` is the full-screen, non-interactive one.)
hl.bind(mainMod .. " + P", hl.dsp.global("caelestia:screenshot"), { locked = true })
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.global("caelestia:screenshotFreeze"), { locked = true })

-- ---- overview (niri Mod+O) / launcher (niri Mod+Space) ----------------------
hl.bind(mainMod .. " + O", hl.dsp.exec_cmd("caelestia toggle dashboard"))
hl.bind(mainMod .. " + Space", hl.dsp.exec_cmd("vicinae toggle"))

-- ---- monitors: focus (niri Mod+Shift+arrows/H/L), move (+Ctrl) --------------
hl.bind(mainMod .. " + SHIFT + Left",  hl.dsp.focus({ monitor = "left" }))
hl.bind(mainMod .. " + SHIFT + Right", hl.dsp.focus({ monitor = "right" }))
hl.bind(mainMod .. " + SHIFT + Up",    hl.dsp.focus({ monitor = "up" }))
hl.bind(mainMod .. " + SHIFT + Down",  hl.dsp.focus({ monitor = "down" }))
hl.bind(mainMod .. " + SHIFT + H",     hl.dsp.focus({ monitor = "left" }))
hl.bind(mainMod .. " + SHIFT + L",     hl.dsp.focus({ monitor = "right" }))
hl.bind(mainMod .. " + SHIFT + CTRL + Left",  hl.dsp.window.move({ monitor = "left" }))
hl.bind(mainMod .. " + SHIFT + CTRL + Right", hl.dsp.window.move({ monitor = "right" }))
hl.bind(mainMod .. " + SHIFT + CTRL + Up",    hl.dsp.window.move({ monitor = "up" }))
hl.bind(mainMod .. " + SHIFT + CTRL + Down",  hl.dsp.window.move({ monitor = "down" }))
hl.bind(mainMod .. " + SHIFT + CTRL + H",     hl.dsp.window.move({ monitor = "left" }))
hl.bind(mainMod .. " + SHIFT + CTRL + L",     hl.dsp.window.move({ monitor = "right" }))

-- ---- lock (niri Super+Alt+L) -> caelestia lock ------------------------------
hl.bind(mainMod .. " + ALT + L", hl.dsp.global("caelestia:lock"))

-- ---- mouse: Mod+LMB drag move, Mod+RMB drag resize (stock hyprland) ---------
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- ---- apps (niri parity) -------------------------------------------------------
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd("ghostty"))
hl.bind(mainMod .. " + T",      hl.dsp.exec_cmd("wezterm"))
hl.bind(mainMod .. " + B",      hl.dsp.exec_cmd("flatpak run app.zen_browser.zen"))
hl.bind(mainMod .. " + F",      hl.dsp.exec_cmd("nautilus --new-window"))
hl.bind(mainMod .. " + M",      hl.dsp.exec_cmd("hyprctl dispatch 'hl.dsp.exit()'"))

-- ---- media keys (pipewire direct; caelestia panel also works) ----------------
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"), { locked = true, repeating = true })

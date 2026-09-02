-- Hyprland config — Caelestia trial (2026-09-01)
--
-- Lua format: hyprlang .conf support is REMOVED in Hyprland 0.57 (this
-- image ships 0.56), so the config is Lua from day one.
--
-- Deliberately minimal: boot Hyprland with the Caelestia shell running and
-- Vicinae bound to the same Super+Space muscle memory as niri. The full
-- Caelestia "dots" experience (their managed Lua config with hypr-vars
-- overrides) is the alternative — if this trial graduates, `caelestia
-- install` writes their tree instead.

local mainMod = "SUPER"

-- niri parity: the laptop panel runs 1920x1200@60 at scale 1.0 (see
-- bubblebox/files/.config/niri/config.kdl). scale "auto" would pick 1.5
-- on this panel — pin it like niri does.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")
hl.env("XCURSOR_SIZE", "24")

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

-- Launcher: same muscle memory as niri (the vicinae daemon itself runs as
-- a user unit via the graphical session above)
hl.bind(mainMod .. " + Space", hl.dsp.exec_cmd("vicinae toggle"))

-- Minimal escape-hatch binds (Caelestia defines the full set)
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd("ghostty"))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("hyprctl dispatch 'hl.dsp.exit()'"))

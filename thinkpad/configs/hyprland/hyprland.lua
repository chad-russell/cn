-- Hyprland configuration (Lua, v0.55+)
-- Translated from niri config for a consistent experience.
-- Start from TTY: Hyprland
-- Config is reloaded on save. Use `hyprctl reload` to force-reload.

------------------
---- MONITORS ----
------------------

-- NOTE: Monitor names may differ from niri. Run `hyprctl monitors` after
-- starting Hyprland and adjust names here if needed.

hl.monitor({
	output = "eDP-1",
	mode = "1920x1200@60",
	position = "2100x1080",
	scale = 1.0,
})

hl.monitor({
	output = "DP-5",
	mode = "3840x2160@60",
	position = "1920x0",
	scale = 1.25,
})

hl.monitor({
	output = "DP-6",
	mode = "3840x2160@60",
	position = "0x0",
	scale = 1.25,
})

-- Fallback for any unmatched display
hl.monitor({
	output = "",
	mode = "preferred",
	position = "auto",
	scale = "auto",
})

-- Autostart: set up systemd integration (niri does this natively,
-- Hyprland does not). The real env export happens in the wrapper script.
hl.on("hyprland.start", function()
	os.execute(
		"systemctl --user import-environment DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE 2>/dev/null"
	)
	os.execute(
		"dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE 2>/dev/null"
	)
	os.execute("systemctl --user start graphical-session.target &")

	-- XWayland bridge (niri does this natively, Hyprland needs it explicit)
	os.execute("xwayland-satellite &")
end)

---------------------
---- MY PROGRAMS ----
---------------------

local terminal = "ghostty"
local fileManager = "nautilus --new-window"
local browser = "flatpak run app.zen_browser.zen"

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("XCURSOR_SIZE", "18")
hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")

-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
	general = {
		gaps_in = 8,
		gaps_out = 8,
		border_size = 2,

		col = {
			active_border = "rgba(33ccffee)",
			inactive_border = "rgba(595959aa)",
		},

		layout = "monocle",
	},

	decoration = {
		rounding = 12,
		rounding_power = 2,

		active_opacity = 1.0,
		inactive_opacity = 1.0,

		shadow = {
			enabled = true,
			range = 4,
			render_power = 3,
			color = 0xee1a1a1a,
		},

		blur = {
			enabled = true,
			size = 3,
			passes = 1,
			vibrancy = 0.1696,
		},
	},

	animations = {
		enabled = true,
	},
})

-- ── Animation curves (niri-inspired critically-damped springs) ─────────
-- Niri uses damping-ratio=1.0 (critically damped) with stiffness 800-1000.
-- Critically damped = fastest settling without any bounce or overshoot.
-- ζ = dampening / (2 * √(mass * stiffness)); we want ζ ≈ 1.0.

-- Stiff spring for snappy window/workspace movement (like niri stiffness=1000)
hl.curve("snappy", { type = "spring", mass = 1, stiffness = 1000, dampening = 63 })
-- Slightly softer for open/close (like niri stiffness=800)
hl.curve("smooth", { type = "spring", mass = 1, stiffness = 800, dampening = 57 })
-- Gentle spring for fades and secondary effects
hl.curve("gentle", { type = "spring", mass = 1, stiffness = 500, dampening = 45 })
-- Keep linear for things that shouldn't ease
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })

-- ── Animations ────────────────────────────────────────────────────────

hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 8, spring = "smooth" })
hl.animation({ leaf = "windows", enabled = true, speed = 8, spring = "snappy" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 8, spring = "smooth", style = "slide" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 8, spring = "smooth", style = "slide" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 8, spring = "gentle" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 8, spring = "gentle" })
hl.animation({ leaf = "fade", enabled = true, speed = 8, spring = "smooth" })
hl.animation({ leaf = "layers", enabled = true, speed = 8, spring = "smooth" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 8, spring = "smooth" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 8, spring = "smooth" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 8, spring = "gentle" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 8, spring = "gentle" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 8, spring = "snappy" })
hl.animation({ leaf = "workspacesIn", enabled = true, speed = 8, spring = "snappy" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 8, spring = "snappy" })

-- Monocle layout: each window takes full screen, cycle through them.
-- Use hl.dsp.layout("cyclenext") / hl.dsp.layout("cycleprev") to navigate.

-- Alt+Tab / Alt+Shift+Tab to cycle windows in monocle
hl.bind("ALT + tab", hl.dsp.layout("cyclenext"))
hl.bind("ALT + SHIFT + tab", hl.dsp.layout("cycleprev"))

----------------
----  MISC  ----
----------------

hl.config({
	misc = {
		force_default_wallpaper = 0, -- No anime mascot
		disable_hyprland_logo = true,
	},
})

-- 3-finger swipe to switch workspaces (like niri)
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

---------------
---- INPUT ----
---------------

hl.config({
	input = {
		kb_layout = "us",
		kb_options = "caps:swapescape",

		follow_mouse = 1,
		sensitivity = 0, -- No modification

		touchpad = {
			natural_scroll = true,
			tap_to_click = true,
			scroll_factor = 0.18,
		},
	},
})

---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "SUPER"

-- ── Window focus (vim + arrows) ──────────────────────────────────────

hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + H", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + J", hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + K", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + L", hl.dsp.focus({ direction = "right" }))

-- ── Window movement ──────────────────────────────────────────────────

hl.bind(mainMod .. " + CTRL + left", hl.dsp.window.move({ direction = "l" }))
hl.bind(mainMod .. " + CTRL + right", hl.dsp.window.move({ direction = "r" }))
hl.bind(mainMod .. " + CTRL + H", hl.dsp.window.move({ direction = "l" }))
hl.bind(mainMod .. " + CTRL + L", hl.dsp.window.move({ direction = "r" }))

-- Toggle split (dwindle only, no-op in monocle)
hl.bind(mainMod .. " + bracketleft", hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + bracketright", hl.dsp.layout("togglesplit"))

-- Monocle: cycle through windows
hl.bind(mainMod .. " + SHIFT + bracketleft", hl.dsp.layout("cycleprev"))
hl.bind(mainMod .. " + SHIFT + bracketright", hl.dsp.layout("cyclenext"))

-- Move to adjacent workspace
hl.bind(mainMod .. " + CTRL + down", hl.dsp.window.move({ workspace = "e+1" }))
hl.bind(mainMod .. " + CTRL + J", hl.dsp.window.move({ workspace = "e+1" }))
hl.bind(mainMod .. " + CTRL + up", hl.dsp.window.move({ workspace = "e-1" }))
hl.bind(mainMod .. " + CTRL + K", hl.dsp.window.move({ workspace = "e-1" }))

-- ── Window resize ────────────────────────────────────────────────────

hl.bind(mainMod .. " + minus", hl.dsp.window.resize({ x = -60, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + equal", hl.dsp.window.resize({ x = 60, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + SHIFT + minus", hl.dsp.window.resize({ x = 0, y = -60, relative = true }), { repeating = true })
hl.bind(mainMod .. " + SHIFT + equal", hl.dsp.window.resize({ x = 0, y = 60, relative = true }), { repeating = true })

-- ── Window actions ───────────────────────────────────────────────────

-- Screenshot (area select → save to ~/Pictures/Screenshots/)
hl.bind(
	mainMod .. " + P",
	hl.dsp.exec_cmd(
		"mkdir -p ~/Pictures/Screenshots && grim -g \"$(slurp)\" ~/Pictures/Screenshots/$(date +'%Y-%m-%d_%H-%M-%S').png"
	)
)

-- Toggle floating
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))

-- Switch focus between floating and tiling (closest equivalent)
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.focus({ last = true }))

-- Close window
hl.bind(mainMod .. " + Q", hl.dsp.window.close())

-- Toggle group (tabbed display equivalent)
hl.bind(mainMod .. " + W", hl.dsp.group.toggle())

-- Maximize (fullscreen with gaps, like niri maximize-column)
hl.bind(mainMod .. " + X", hl.dsp.window.fullscreen({ mode = "maximized" }))

-- True fullscreen
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))

-- ── Workspace switcher (vicinae) ─────────────────────────────────────

hl.bind(mainMod .. " + space", hl.dsp.exec_cmd("vicinae toggle"))

-- ── Workspace navigation (prev/next) ─────────────────────────────────

hl.bind(mainMod .. " + SHIFT + J", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + SHIFT + L", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + SHIFT + K", hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + SHIFT + H", hl.dsp.focus({ workspace = "e-1" }))

-- ── Monitor focus ────────────────────────────────────────────────────

hl.bind(mainMod .. " + SHIFT + left", hl.dsp.focus({ monitor = "l" }))
hl.bind(mainMod .. " + SHIFT + H", hl.dsp.focus({ monitor = "l" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.focus({ monitor = "r" }))
hl.bind(mainMod .. " + SHIFT + L", hl.dsp.focus({ monitor = "r" }))
hl.bind(mainMod .. " + SHIFT + down", hl.dsp.focus({ monitor = "d" }))
hl.bind(mainMod .. " + SHIFT + up", hl.dsp.focus({ monitor = "u" }))

-- ── Move to monitor ──────────────────────────────────────────────────

hl.bind(mainMod .. " + CTRL + SHIFT + left", hl.dsp.window.move({ monitor = "l" }))
hl.bind(mainMod .. " + CTRL + SHIFT + right", hl.dsp.window.move({ monitor = "r" }))
hl.bind(mainMod .. " + CTRL + SHIFT + H", hl.dsp.window.move({ monitor = "l" }))
hl.bind(mainMod .. " + CTRL + SHIFT + L", hl.dsp.window.move({ monitor = "r" }))
hl.bind(mainMod .. " + CTRL + SHIFT + down", hl.dsp.window.move({ monitor = "d" }))
hl.bind(mainMod .. " + CTRL + SHIFT + up", hl.dsp.window.move({ monitor = "u" }))
hl.bind(mainMod .. " + CTRL + SHIFT + J", hl.dsp.window.move({ monitor = "d" }))
hl.bind(mainMod .. " + CTRL + SHIFT + K", hl.dsp.window.move({ monitor = "u" }))

-- ── Power control ────────────────────────────────────────────────────

hl.bind(mainMod .. " + SHIFT + P", hl.dsp.dpms({ action = "off" }))

-- ── Noctalia keybinds ────────────────────────────────────────────────

hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("noctalia-shell ipc call notifications toggleDND"))
hl.bind(mainMod .. " + comma", hl.dsp.exec_cmd("noctalia-shell ipc call settings toggle"))
hl.bind(mainMod .. " + ALT + L", hl.dsp.exec_cmd("noctalia-shell ipc call lockScreen lock"))
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("noctalia-shell ipc call systemMonitor toggle"))
hl.bind(mainMod .. " + ALT + N", hl.dsp.exec_cmd("noctalia-shell ipc call nightLight toggle"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd("noctalia-shell ipc call sessionMenu toggle"))

-- ── Applications ─────────────────────────────────────────────────────

hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + F", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("voxtype record toggle"))

-- ── Media keys (Noctalia) ────────────────────────────────────────────

hl.bind(
	"XF86AudioRaiseVolume",
	hl.dsp.exec_cmd("noctalia-shell ipc call volume increase"),
	{ locked = true, repeating = true }
)
hl.bind(
	"XF86AudioLowerVolume",
	hl.dsp.exec_cmd("noctalia-shell ipc call volume decrease"),
	{ locked = true, repeating = true }
)
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("noctalia-shell ipc call volume muteOutput"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("noctalia-shell ipc call volume muteInput"), { locked = true })
hl.bind(
	"XF86MonBrightnessUp",
	hl.dsp.exec_cmd("noctalia-shell ipc call brightness increase"),
	{ locked = true, repeating = true }
)
hl.bind(
	"XF86MonBrightnessDown",
	hl.dsp.exec_cmd("noctalia-shell ipc call brightness decrease"),
	{ locked = true, repeating = true }
)

-- ── Numbered workspaces (1-10) ───────────────────────────────────────

for i = 1, 10 do
	local key = i % 10 -- 10 maps to key 0
	-- Switch to workspace
	hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
	-- Move window to workspace (follows the window)
	hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i, follow = true }))
	-- Move window to workspace silently (stays on current workspace)
	hl.bind(mainMod .. " + CTRL + " .. key, hl.dsp.window.move({ workspace = i, follow = false }))
end

-- ── Mouse binds ──────────────────────────────────────────────────────

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Scroll through workspaces
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- Firefox Picture-in-Picture
hl.window_rule({
	name = "firefox-pip",
	match = { class = "^firefox$", title = "^Picture-in-Picture$" },
	float = true,
})

-- Zoom floating windows
hl.window_rule({
	name = "zoom-menu",
	match = { class = "Zoom Workplace", title = ".*menu.*" },
	float = true,
})

hl.window_rule({
	name = "zoom-settings",
	match = { class = "Zoom Workplace", title = "Settings" },
	float = true,
})

hl.window_rule({
	name = "zoom-audio",
	match = { class = "Zoom Workplace", title = "Audio Settings" },
	float = true,
})

hl.window_rule({
	name = "zoom-sharing",
	match = { class = "Zoom Workplace", title = ".*Sharing.*" },
	float = true,
})

hl.window_rule({
	name = "zoom-chat",
	match = { class = "Zoom Workplace", title = "Chat" },
	float = true,
})

-- Suppress maximize requests from all apps
hl.window_rule({
	name = "suppress-maximize",
	match = { class = ".*" },
	suppress_event = "maximize",
})

-- Fix XWayland drag issues with empty class/title
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

-- Noctalia overview layer rule
hl.layer_rule({
	name = "noctalia-overview",
	match = { namespace = "^noctalia-overview.*" },
})

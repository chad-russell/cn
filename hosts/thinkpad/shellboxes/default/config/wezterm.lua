-- wezterm config for the shellbox `default` box.
--
-- wezterm itself runs inside the box; each tab/pane's shell runs on the HOST
-- via `wezterm-host-shell` (systemd-run --user --pty). See ../wezterm-host-shell
-- and ../shellbox.toml (WEZTERM_CONFIG_FILE points wezterm here).
--
-- This is a starter config — extend freely. Keys/options here are only the
-- ones that matter for the shellbox setup.

local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- Per-pane shell lives on the host, not in the box.
config.default_prog = { '/usr/local/bin/wezterm-host-shell' }

-- WebGpu exercises the forwarded /dev/dri + /sys; it falls back to OpenGL
-- automatically if no GPU is available.
config.front_end = 'WebGpu'

return config

-- wezterm config for the bubblebox wezterm sandbox.
--
-- wezterm itself runs inside the sandbox; each tab/pane's shell runs on the
-- HOST via `bubblebox-host-shell` (systemd-run --user --pty).

local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- Per-pane shell lives on the host, not in the box.
config.default_prog = { '/usr/local/bin/bubblebox-host-shell' }

-- OpenGL is the more forgiving choice inside the bubblebox sandbox: it still
-- uses the forwarded render node, but doesn't depend on Vulkan/Zink working.
config.front_end = 'OpenGL'

-- Don't prompt when closing the last window / quitting.
config.window_close_confirmation = 'NeverPrompt'

-- Drop ALL window decorations; niri handles rounded corners and resize.
config.window_decorations = 'NONE'

-- Tabs: neovim-tabline style — flat, clean, no noise.
config.enable_tab_bar = true
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = false


config.colors = {
  tab_bar = {
    background = '#1e1e2e',
    active_tab = {
      bg_color = '#2d3f76',

      fg_color = '#d9d7ce',
    },
    inactive_tab = {
      bg_color = '#232637',
      fg_color = '#5c6773',
    },
    inactive_tab_hover = {
      bg_color = '#2d3f76',
      fg_color = '#d9d7ce',
    },
    new_tab = {
      bg_color = '#1e1e2e',
      fg_color = '#5c6773',
    },
    new_tab_hover = {
      bg_color = '#2d3f76',
      fg_color = '#d9d7ce',
    },
  },
}

-- A tiling WM doesn't need min/max/close buttons in the tab bar either — Mod+Q
-- (and niri's other binds) cover window control. Empty list = no buttons, so
-- the tab bar is purely tabs + the new-tab '+' button.
config.integrated_title_buttons = {}

-- Coherent palette across terminal + tab bar (wezterm applies the scheme's
-- tab_bar colors automatically). Swap freely; wezterm ships hundreds.
-- Alternatives: 'Ayu Dark' (warmer), 'Tokyo Night', 'Zenbones Dark' (vicinae).
config.color_scheme = 'Ayu Mirage'

-- Keep the shell/app-provided tab title, but strip wezterm's leading activity
-- indicator so tabs read like a normal terminal title bar.
wezterm.on('format-tab-title', function(tab, tabs, panes, config, hover, max_width)
  local title = tab.tab_title
  if title == nil or title == '' then
    title = tab.active_pane.title or ''
  end

  title = title:gsub('^%s*[🟡🟠🔴🟢🔵🟣🟤🟨🟧🟥🟩🟦🟪🟫●•]+%s*', '')
  title = title:gsub('^%s*%d+:%s*', '')
  title = wezterm.truncate_right(title, max_width - 2)

  local bg, fg
  if tab.is_active or hover then
    bg, fg = '#2d3f76', '#d9d7ce'
  else
    bg, fg = '#232637', '#5c6773'
  end

  return {
    { Background = { Color = bg } },
    { Foreground = { Color = fg } },
    { Text = ' ' .. title .. ' ' },
  }
end)

return config

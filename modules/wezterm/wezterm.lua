-- Pull in the wezterm API
local wezterm = require("wezterm")

-- This table will hold the configuration.
local config = {}

-- In newer versions of wezterm, use the config_builder which will help
-- ensure that the config is valid.
if wezterm.config_builder then
    config = wezterm.config_builder()
end

-- Wayland == no good
config.enable_wayland = false

-- General appearance
config.color_scheme = "Earthsong"
config.window_decorations = "RESIZE"

-- Use zsh
config.default_prog = { '/etc/profiles/per-user/crussell/bin/zsh', '-l' }

-- Font configuration
config.font = wezterm.font("JetBrains Mono")
config.font_size = 14.0
config.line_height = 1.2

-- Cursor colors (keep these separate)
config.colors = {
    cursor_bg = "#D3C6AA",
    cursor_border = "#D3C6AA",
}

-- Enable and style the tab bar: flat minimal tabs
config.enable_tab_bar = true
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = true
config.tab_max_width = 24

-- cursor
config.animation_fps = 120
config.cursor_blink_ease_in = 'EaseOut'
config.cursor_blink_ease_out = 'EaseOut'
config.default_cursor_style = 'BlinkingBlock'
config.cursor_blink_rate = 650

-- Tab bar color groups (themed to Everforest palette)
config.colors = config.colors or {}
config.colors.tab_bar = {
    background = "#272E33",
    active_tab = { bg_color = "#374145", fg_color = "#D3C6AA" },
    inactive_tab = { bg_color = "#272E33", fg_color = "#859289" },
    inactive_tab_hover = { bg_color = "#2E383C", fg_color = "#9DA9A0" },
    new_tab = { bg_color = "#272E33", fg_color = "#7FB4B3" },
    new_tab_hover = { bg_color = "#2E383C", fg_color = "#7FB4B3" },
}

-- Move tab title formatting into an event handler so the config table
-- itself contains no raw Lua functions (which prevents serialization errors).
--
-- This replaces assigning `config.format_tab_title = function(...) ... end`
-- which can cause `lua_value_to_dynamic` / serialization issues.
wezterm.on("format-tab-title", function(tab, tabs, panes, cfg)
    local wez = require("wezterm")
    local title = tab.tab_title or tab.active_pane.title or ("#" .. tostring(tab.tab_index + 1))
    local index = tostring(tab.tab_index + 1)
    local is_active = tab.is_active

    local fg = is_active and "#D3C6AA" or "#859289"
    local bg = is_active and "#374145" or "#272E33"

    return wez.format({
        { Background = { Color = bg } }, { Foreground = { Color = fg } },
        { Text = " " .. index .. " " .. title .. " " },
    })
end)

-- Key bindings
config.keys = {
    -- New Tab
    { key = 't', mods = 'CTRL',       action = wezterm.action.SpawnTab 'DefaultDomain', },
    { key = 'w', mods = 'CTRL',       action = wezterm.action.CloseCurrentPane { confirm = false }, },

    -- Next/Previous Tab
    { key = 'l', mods = 'CTRL|SHIFT', action = wezterm.action.ActivateTabRelative(1), },
    { key = 'h', mods = 'CTRL|SHIFT', action = wezterm.action.ActivateTabRelative(-1), },

    -- Key Table (Prefix)
    {
        key = 'b',
        mods = 'CTRL',
        action = wezterm.action.ActivateKeyTable {
            name = "b",
            one_shot = true,
            timeout_milliseconds = 1000,
        }
    },

    -- Pane navigation
    { key = 'h', mods = 'ALT',        action = wezterm.action.ActivatePaneDirection 'Left', },
    { key = 'j', mods = 'ALT',        action = wezterm.action.ActivatePaneDirection 'Down', },
    { key = 'k', mods = 'ALT',        action = wezterm.action.ActivatePaneDirection 'Up', },
    { key = 'l', mods = 'ALT',        action = wezterm.action.ActivatePaneDirection 'Right', },

    -- Toggle pane zoom
    { key = 'y', mods = 'CTRL',       action = wezterm.action.TogglePaneZoomState, },

    -- Copy/Paste
    { key = 'c', mods = 'CTRL|SHIFT', action = wezterm.action.CopyTo('Clipboard') },
    { key = 'v', mods = 'CTRL|SHIFT', action = wezterm.action.PasteFrom('Clipboard') },

    -- Launchers
    { key = 'o', mods = 'CMD',        action = wezterm.action.ShowLauncher },
    { key = 'p', mods = 'CMD',        action = wezterm.action.ActivateCommandPalette },
    { key = 'p', mods = 'CMD|SHIFT',  action = wezterm.action.ShowLauncherArgs({ flags = 'FUZZY|TABS' }) },

    { key = 'f', mods = 'CMD',        action = wezterm.action.Search({ CaseInSensitiveString = '' }) },
}

-- Key tables (for modal bindings)
config.key_tables = {
    b = {
        {
            key = 'h',
            action = wezterm.action.SplitPane {
                direction = 'Left',
                size = { Percent = 50 },
            },
        },
        {
            key = 'l',
            action = wezterm.action.SplitPane {
                direction = 'Right',
                size = { Percent = 50 },
            },
        },
        {
            key = 'k',
            action = wezterm.action.SplitPane {
                direction = 'Up',
                size = { Percent = 50 },
            },
        },
        {
            key = 'j',
            action = wezterm.action.SplitPane {
                direction = 'Down',
                size = { Percent = 50 },
            },
        },
        -- Rename Tab
        {
            key = 'r',
            action = wezterm.action.PromptInputLine {
                description = 'Enter new tab title:',
                action = wezterm.action_callback(function(window, pane, line)
                    if line then
                        window:active_tab():set_title(line)
                    end
                end),
            },
        },
        {
            key = 'f',
            action = wezterm.action.ActivateKeyTable {
                name = "resize_font",
                one_shot = false,
                timeout_milliseconds = 1000,
            },
        },
    },
    resize_font = {
        { key = 'k',      action = wezterm.action.IncreaseFontSize },
        { key = 'j',      action = wezterm.action.DecreaseFontSize },
        { key = 'r',      action = wezterm.action.ResetFontSize },
        { key = 'Escape', action = wezterm.action.PopKeyTable },
        { key = 'q',      action = wezterm.action.PopKeyTable },
    },
}

-- Disable the default keybindings for showing the launcher
config.disable_default_key_bindings = true

-- Window padding
config.window_padding = {
    left = 10,
    right = 10,
    top = 10,
    bottom = 10,
}

-- Return the configuration to wezterm
return config

-- Neovim config for the bubblebox "nvim" tool.
--
-- Vendored into the image at /usr/share/bubblebox/nvim/ and loaded because
-- tools/nvim/profile sets XDG_CONFIG_HOME=/usr/share/bubblebox (nvim reads
-- $XDG_CONFIG_HOME/nvim). Plugin/state/cache are isolated to a bubblebox-owned
-- dir via XDG_DATA/STATE/CACHE_HOME — see the profile. Edit this config, then
-- `bubblebox-build nvim && bubblebox-mount nvim` to pick up changes.

-- Speed up lua module loading. Must be first.
vim.loader.enable()

-- =========================================================================
-- Bootstrap lazy.nvim (plugin manager)
-- =========================================================================
-- Plugin data lives at stdpath("data")/lazy = ~/.local/share/nvim/lazy, which
-- is in the shared host $HOME and so survives toolbox recreations. Only the
-- *config* (this directory) is rebuild-managed; installed plugins are cached
-- per-user.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  local repo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", repo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit...", "WarningMsg" },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

-- Core vim config (cheap, always-on; load before plugins).
require("config.options")
require("config.keymaps")

-- Plugin specs live in lua/plugins/*.lua (auto-discovered).
-- lazy-lock.json is runtime data (changes as plugins update), so keep it in the
-- writable data dir — not the read-only vendored config. Seed it from the
-- vendored lock on first run so the pinned commits are respected.
local lazy_lock = vim.fn.stdpath("data") .. "/lazy-lock.json"
if vim.uv.fs_stat(lazy_lock) == nil then
  local vendored = vim.fn.stdpath("config") .. "/lazy-lock.json"
  if vim.uv.fs_stat(vendored) ~= nil then
    vim.fn.writefile(vim.fn.readfile(vendored), lazy_lock)
  end
end
require("lazy").setup("plugins", {
  lockfile = lazy_lock,
  install = { missing = true, colorscheme = { "everforest" } },
  -- Don't nag during iteration:
  checker = { enabled = true, notify = false },
  change_detection = { notify = false },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip", "tarPlugin", "tohtml", "tutor", "zipPlugin",
        "netrwPlugin", -- neo-tree replaces netrw
      },
    },
  },
})

-- LSP + autocmds (native vim.lsp on 0.11+; no LSP plugin needed).
require("config.autocmds")
require("config.lsp")

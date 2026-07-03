-- Neovim config for the dev toolbox.
--
-- Source of truth: hosts/thinkpad/toolbox/shell/nvim/ (this directory).
-- Baked into the image at /usr/share/dev-shell/nvim/ and loaded because the
-- Containerfile sets XDG_CONFIG_HOME=/usr/share/dev-shell (nvim reads
-- $XDG_CONFIG_HOME/nvim).
--
-- FAST ITERATION (no rebuild): mount the working copy over the baked path:
--   podman run ... -v .../toolbox/shell/nvim:/usr/share/dev-shell/nvim:Z
-- Then every `nvim` reads the live repo files — edit, restart nvim, see
-- changes. Run ./nvim-check.sh to headless-boot + Lazy sync and paste errors.

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
require("lazy").setup("plugins", {
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

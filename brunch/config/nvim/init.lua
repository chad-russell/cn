-- Leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Disable netrw (file explorer) in favor of neo-tree
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Disable unused providers (cleans up healthcheck warnings)
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0

-- Nerd font support
vim.g.have_nerd_font = true

-- Speed up Lua module loading
vim.loader.enable()

-- Disable default Tab/S-Tab snippet mappings (we use Tab for buffer cycling,
-- and C-n/C-p for snippet jumping instead)
vim.keymap.del({ 'i', 's' }, '<Tab>')
vim.keymap.del({ 'i', 's' }, '<S-Tab>')

-- Load configuration modules
require('options')
require('keymaps')

-- Enable built-in autocompletion with LSP
-- Uses native vim.lsp.completion + vim.snippet instead of nvim-cmp/LuaSnip
vim.opt.completeopt:append({ "menuone", "noselect", "popup" })
vim.opt.autocomplete = true

-- Popup menu border (Neovim 0.12)
vim.opt.pumborder = "rounded"

-- Plugin hooks (must be before first vim.pack.add for install hooks to work)
vim.api.nvim_create_autocmd('PackChanged', { callback = function(ev)
  local name, kind = ev.data.spec.name, ev.data.kind
  -- Update tree-sitter parsers when nvim-treesitter is installed/updated
  if name == 'nvim-treesitter' and (kind == 'install' or kind == 'update') then
    if not ev.data.active then vim.cmd.packadd('nvim-treesitter') end
    vim.cmd('TSUpdate')
  end
  -- Run MasonUpdate after mason installs/updates
  if name == 'mason.nvim' and (kind == 'install' or kind == 'update') then
    if not ev.data.active then vim.cmd.packadd('mason.nvim') end
    vim.cmd('MasonUpdate')
  end
  -- Build telescope-fzf-native
  if name == 'telescope-fzf-native.nvim' and (kind == 'install' or kind == 'update') then
    vim.system({ 'make' }, { cwd = ev.data.path })
  end
end })

-- Helper for shorter GitHub URLs
local gh = function(repo) return 'https://github.com/' .. repo end

-- Colorscheme (load first)
vim.pack.add({
  gh('sainnhe/everforest'),
  gh('nvim-tree/nvim-web-devicons'),
})
vim.g.everforest_enable_italic = true
vim.g.everforest_better_performance = true
vim.g.everforest_background = "hard"
vim.cmd.colorscheme("everforest")

-- Bufferline (VSCode-like tabs)
vim.pack.add({ gh('akinsho/bufferline.nvim') })
require('bufferline').setup({
  options = {
    mode = "buffers",
    separator_style = "thin",
    always_show_bufferline = true,
    show_buffer_close_icons = true,
    show_close_icon = false,
    diagnostics = "nvim_lsp",
    offsets = {
      {
        filetype = "neo-tree",
        text = "File Explorer",
        highlight = "Directory",
        text_align = "left",
      },
    },
  },
})

-- Mason: Install LSP servers, formatters, etc.
vim.pack.add({ gh('williamboman/mason.nvim') })
require("mason").setup({
  ui = {
    border = "rounded",
    icons = {
      package_installed = "✓",
      package_pending = "➜",
      package_uninstalled = "✗",
    },
  },
})

-- LSP configuration (native vim.lsp.config + vim.lsp.enable)
require('plugins.lsp')

-- Code formatting (lazy load on first write)
vim.api.nvim_create_autocmd('BufWritePre', { once = true, callback = function()
  vim.pack.add({ gh('stevearc/conform.nvim') })
  require('plugins.conform')
end })

-- Git signs (lazy load on first file read)
vim.api.nvim_create_autocmd({ 'BufReadPre', 'BufNewFile' }, { once = true, callback = function()
  vim.pack.add({ gh('lewis6991/gitsigns.nvim') })
  require('plugins.gitsigns')
end })

-- Comment toggling (lazy load on gc/gb keys)
vim.keymap.set({ 'n', 'x' }, 'gc', function()
  vim.keymap.del({ 'n', 'x' }, 'gc')
  vim.keymap.del({ 'n', 'x' }, 'gb')
  vim.pack.add({ gh('numToStr/Comment.nvim') })
  require('plugins.comment')
  return '<Plug>(comment_toggle_linewise)'
end, { expr = true, desc = 'Comment toggle' })

vim.keymap.set({ 'n', 'x' }, 'gb', function()
  vim.keymap.del({ 'n', 'x' }, 'gb')
  vim.pack.add({ gh('numToStr/Comment.nvim') })
  require('plugins.comment')
  return '<Plug>(comment_toggle_blockwise)'
end, { expr = true, desc = 'Comment toggle block' })

-- Flash (lazy load via schedule)
vim.schedule(function()
  vim.pack.add({ gh('folke/flash.nvim') })
  require('plugins.flash')
end)

-- Session persistence (lazy load on first file read)
vim.api.nvim_create_autocmd('BufReadPre', { once = true, callback = function()
  vim.pack.add({ gh('folke/persistence.nvim') })
  require('plugins.persistence')
end })

-- Code outline
vim.pack.add({ gh('stevearc/aerial.nvim') })
require('plugins.aerial')

-- Diagnostics list
vim.pack.add({ gh('folke/trouble.nvim') })
require('plugins.trouble')

-- File explorer
vim.pack.add({
  gh('nvim-neo-tree/neo-tree.nvim'),
  gh('MunifTanjim/nui.nvim'),
})
require('plugins.neo-tree')

-- Fuzzy finder
vim.pack.add({
  gh('nvim-telescope/telescope.nvim'),
  gh('nvim-lua/plenary.nvim'),
  gh('nvim-telescope/telescope-fzf-native.nvim'),
})
require('plugins.telescope')

-- Syntax highlighting
vim.pack.add({ gh('nvim-treesitter/nvim-treesitter') })
require('plugins.treesitter')

-- Which-key
vim.schedule(function()
  vim.pack.add({ gh('folke/which-key.nvim') })
  require('plugins.which-key')
end)

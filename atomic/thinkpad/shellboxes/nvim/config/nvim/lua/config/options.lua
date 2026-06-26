-- vim options. Ported from thinkpad/nvim/default.nix `opts` + extraConfigLua.

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Disable built-in providers we don't use (avoid startup warnings).
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0

-- Disable netrw (neo-tree replaces it).
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Nerd font is installed in the toolbox image.
vim.g.have_nerd_font = true

local opt = vim.opt

-- Cursor
opt.guicursor = "n-v-c:block,i-ci-ve:ver25,r-cr:hor20,o:hor50"

-- Line numbers
opt.number = true
opt.relativenumber = true
opt.cursorline = true
opt.signcolumn = "yes"
opt.showtabline = 2

-- Indentation / tabs
opt.tabstop = 4
opt.softtabstop = 4
opt.shiftwidth = 4
opt.expandtab = true
opt.smartindent = true

-- Text display
opt.wrap = false
opt.termguicolors = true
opt.scrolloff = 8
opt.cmdheight = 1

-- File handling
opt.swapfile = false
opt.backup = false
opt.undofile = true

-- Search
opt.hlsearch = false
opt.incsearch = true
opt.ignorecase = true
opt.smartcase = true

-- Performance / timing
opt.updatetime = 50
opt.timeoutlen = 1000
opt.ttimeoutlen = 0

-- Command preview
opt.inccommand = "split"

-- Native completion (Neovim 0.11+)
opt.completeopt = { "menuone", "noselect", "popup" }
opt.pumblend = 10 -- popup menu transparency (nix: pumborder=rounded; this is the real knob)

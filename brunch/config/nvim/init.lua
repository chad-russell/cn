-- Leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Disable netrw (file explorer) in favor of neo-tree
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Nerd font support
vim.g.have_nerd_font = true

-- Load lazy.nvim plugin manager
require("lazy_setup")

-- Load configuration modules
require('options')
require('keymaps')

-- Load plugins

-- Options configuration converted from nixvim

local opt = vim.opt
local g = vim.g

-- Cursor
opt.guicursor = "n-v-c:block,i-ci-ve:ver25,r-cr:hor20,o:hor50"

-- Line numbers
opt.number = true
opt.relativenumber = true

-- Indentation and tabs
opt.tabstop = 4
opt.softtabstop = 4
opt.shiftwidth = 4
opt.expandtab = true
opt.smartindent = true

-- Text display
opt.wrap = false
opt.cursorline = true

-- File handling
opt.swapfile = false
opt.backup = false
opt.undofile = true
opt.undodir = vim.fn.expand("~/.vim/undodir")

-- Search
opt.hlsearch = false
opt.incsearch = true
opt.ignorecase = true

-- Display
opt.termguicolors = true
opt.scrolloff = 8
opt.signcolumn = "yes"
opt.cmdheight = 1

-- Performance and timing
opt.updatetime = 50
opt.timeoutlen = 1000
opt.ttimeoutlen = 0

-- Command preview
opt.inccommand = "split"

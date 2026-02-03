-- Keymaps configuration converted from nixvim

local keymap = vim.keymap.set
local opts = { noremap = true, silent = true }

-- Command mode
keymap("n", ";", ":", { desc = "CMD enter command mode", noremap = true })

-- Scrolling with centering
keymap("n", "<C-d>", "<C-d>zz", { desc = "Scroll down and center" })
keymap("n", "<C-u>", "<C-u>zz", { desc = "Scroll up and center" })

-- Search navigation with centering
keymap("n", "n", "nzzzv", { desc = "Next search result and center" })
keymap("n", "N", "Nzzzv", { desc = "Previous search result and center" })

-- Join lines
keymap("n", "J", "mzJ`z", { desc = "Join lines and maintain cursor position" })

-- Yank to end of line
keymap("n", "Y", "yg$", { desc = "Yank to end of line" })

-- Movement remaps
keymap({ "n", "v" }, "L", "$", { desc = "Move to end of line" })
keymap({ "n", "v" }, "H", "^", { desc = "Move to start of line" })
keymap({ "n", "v" }, "K", "%", { desc = "Jump to matching bracket" })

-- Disable original movement keys
keymap({ "n", "v" }, "$", "<nop>", { desc = "Disabled: use L instead" })
keymap({ "n", "v" }, "^", "<nop>", { desc = "Disabled: use H instead" })
keymap({ "n", "v" }, "%", "<nop>", { desc = "Disabled: use K instead" })

-- Buffer navigation
keymap("n", "<tab>", "<cmd>bnext<CR>", { desc = "Next buffer" })
keymap("n", "<S-tab>", "<cmd>bprev<CR>", { desc = "Previous buffer" })
keymap("n", "<leader>x", "<cmd>bdelete<CR>", { desc = "Close buffer" })

-- Paste without yanking
keymap("x", "<leader>p", "\"_dP", { desc = "Paste without yanking" })

-- Yank to system clipboard
keymap({ "n", "v" }, "<leader>y", "\"+y", { desc = "Yank to system clipboard" })

-- Delete without yanking
keymap({ "n", "v" }, "<leader>d", "\"_d", { desc = "Delete without yanking" })

-- Disable Q
keymap("n", "Q", "<nop>", { desc = "Disabled: Ex mode" })

-- Window navigation
keymap("n", "<C-h>", "<C-w><C-h>", { desc = "Move focus to the left" })
keymap("n", "<C-l>", "<C-w><C-l>", { desc = "Move focus to the right" })
keymap("n", "<C-j>", "<C-w><C-j>", { desc = "Move focus down" })
keymap("n", "<C-k>", "<C-w><C-k>", { desc = "Move focus up" })

-- Which-key show
keymap("n", "<leader>?", ":lua require('which-key').show({ global = false })<CR>", { desc = "Show which-key mappings", silent = true })

-- General keymaps (non-plugin). Ported from the nixvim module.
-- Plugin-specific keymaps (flash, telescope, trouble, neo-tree, gitsigns,
-- aerial, conform, persistence) live with their plugin specs in
-- lua/plugins/*.lua so they lazy-load correctly.

local map = function(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { desc = desc })
end

-- Command mode
map("n", ";", ":", "CMD enter command mode")

-- Scrolling with centering
map("n", "<C-d>", "<C-d>zz", "Scroll down and center")
map("n", "<C-u>", "<C-u>zz", "Scroll up and center")

-- Search navigation with centering
map("n", "n", "nzzzv", "Next search result and center")
map("n", "N", "Nzzzv", "Previous search result and center")

-- Join lines, keep cursor position
map("n", "J", "mzJ`z", "Join lines and maintain cursor")

-- Yank to end of line
map("n", "Y", "yg$", "Yank to end of line")

-- Movement remaps: L/H for end/start of line
map({ "n", "v" }, "L", "$", "Move to end of line")
map({ "n", "v" }, "H", "^", "Move to start of line")

-- Jump to matching bracket
map({ "n", "v" }, "\\", "%", "Jump to matching bracket")

-- Disable original movement keys (use the remaps above)
map({ "n", "v" }, "$", "<nop>", "Disabled: use L instead")
map({ "n", "v" }, "^", "<nop>", "Disabled: use H instead")
map({ "n", "v" }, "%", "<nop>", "Disabled: use \\ instead")

-- Buffer navigation
map("n", "<tab>", "<cmd>bnext<CR>", "Next buffer")
map("n", "<S-tab>", "<cmd>bprev<CR>", "Previous buffer")
map("n", "<leader>x", "<cmd>bdelete<CR>", "Close buffer")

-- Paste without yanking
map("x", "<leader>p", '"_dP', "Paste without yanking")

-- Yank to system clipboard
map({ "n", "v" }, "<leader>y", '"+y', "Yank to system clipboard")

-- Delete without yanking (black-hole register)
map({ "n", "v" }, "<leader>d", '"_d', "Delete without yanking")

-- Disable Ex mode
map("n", "Q", "<nop>", "Disabled: Ex mode")

-- Window navigation
map("n", "<C-h>", "<C-w><C-h>", "Move focus to the left")
map("n", "<C-l>", "<C-w><C-l>", "Move focus to the right")
map("n", "<C-j>", "<C-w><C-j>", "Move focus down")
map("n", "<C-k>", "<C-w><C-k>", "Move focus up")

-- Native snippet jumping (vim.snippet, no plugin)
vim.keymap.set({ "i", "s" }, "<C-n>", function()
  if vim.snippet.active({ direction = 1 }) then
    vim.snippet.jump(1)
    return
  end
  return "<C-n>"
end, { expr = true, desc = "Snippet jump forward" })

vim.keymap.set({ "i", "s" }, "<C-p>", function()
  if vim.snippet.active({ direction = -1 }) then
    vim.snippet.jump(-1)
    return
  end
  return "<C-p>"
end, { expr = true, desc = "Snippet jump backward" })

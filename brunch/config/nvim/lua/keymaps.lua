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
-- L/H for end/start of line (instead of $/^ which are hard to reach)
-- Note: H conflicts with v_an (LSP selection range) and L with v_in,
-- but these are only active during visual mode with LSP attached.
keymap({ "n", "v" }, "L", "$", { desc = "Move to end of line" })
keymap({ "n", "v" }, "H", "^", { desc = "Move to start of line" })

-- Jump to matching bracket (using \ instead of K, since K = LSP hover in 0.12)
keymap({ "n", "v" }, "\\", "%", { desc = "Jump to matching bracket" })

-- Disable original movement keys
keymap({ "n", "v" }, "$", "<nop>", { desc = "Disabled: use L instead" })
keymap({ "n", "v" }, "^", "<nop>", { desc = "Disabled: use H instead" })
keymap({ "n", "v" }, "%", "<nop>", { desc = "Disabled: use \\ instead" })

-- Snippet jumping: use <C-n>/<C-p> in insert/select mode
-- Alternative options you might prefer:
--   <M-n>/<M-p>  (Alt+n / Alt+p)
--   <C-j>/<C-k>  (conflicts with window nav in normal mode, but fine in insert)
--   <C-l>/<C-h>  (same reasoning)
keymap({ "i", "s" }, "<C-n>", function()
  if vim.snippet.active({ direction = 1 }) then
    vim.snippet.jump(1)
    return
  end
  return "<C-n>"
end, { expr = true, desc = "Snippet jump forward" })

keymap({ "i", "s" }, "<C-p>", function()
  if vim.snippet.active({ direction = -1 }) then
    vim.snippet.jump(-1)
    return
  end
  return "<C-p>"
end, { expr = true, desc = "Snippet jump backward" })

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

-- Which-key show (guard against plugin not yet loaded)
keymap("n", "<leader>?", function()
  local ok, wk = pcall(require, 'which-key')
  if ok then wk.show({ global = false }) end
end, { desc = "Show which-key mappings", silent = true })

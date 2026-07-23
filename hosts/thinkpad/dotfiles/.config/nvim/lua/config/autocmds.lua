-- General autocmds. LSP autocmds live in config/lsp.lua.

local augroup = vim.api.nvim_create_augroup("devshell", { clear = true })

-- Highlight yanked text briefly.
vim.api.nvim_create_autocmd("TextYankPost", {
  group = augroup,
  callback = function()
    vim.highlight.on_yank({ timeout = 200 })
  end,
  desc = "Highlight yank",
})

-- When opening a help/quickfix/man buffer, start on the right side.
vim.api.nvim_create_autocmd("FileType", {
  group = augroup,
  pattern = { "help", "man", "qf" },
  callback = function()
    vim.cmd("wincmd L")
  end,
  desc = "Open help/man/quickfix on the right",
})

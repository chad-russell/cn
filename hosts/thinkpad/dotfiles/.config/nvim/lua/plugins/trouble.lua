-- Trouble: diagnostics / quickfix panel (v3).
-- v3 changed the API: `:Trouble <type> toggle`. Lua: require("trouble").open().
-- If these mappings misbehave after a Trouble update, this is the first
-- place to check during the iteration loop.

return {
  {
    "folke/trouble.nvim",
    branch = "main",
    cmd = "Trouble",
    opts = {},
    keys = {
      { "<leader>xx", "<cmd>Trouble diagnostics toggle<CR>", desc = "Toggle trouble" },
      { "<leader>xw", "<cmd>Trouble diagnostics toggle<CR>", desc = "Workspace diagnostics" },
      { "<leader>xd", "<cmd>Trouble diagnostics toggle filter.buf=0<CR>", desc = "Document diagnostics" },
      { "<leader>xq", "<cmd>Trouble qf list toggle<CR>", desc = "Quickfix list" },
      { "<leader>xl", "<cmd>Trouble loc list toggle<CR>", desc = "Location list" },
      { "gR", "<cmd>Trouble lsp toggle<CR>", desc = "LSP references (trouble)" },
    },
  },
}

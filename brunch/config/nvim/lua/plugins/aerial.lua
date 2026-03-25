require("aerial").setup({
  attach_mode = "global",
  backends = { "lsp", "treesitter", "markdown", "man" },
  show_guides = true,
  layout = {
    min_width = 28,
    default_direction = "prefer_right",
  },
  close_on_select = true,
})

vim.keymap.set("n", "<leader>at", "<cmd>AerialToggle!<CR>", { desc = "Toggle outline" })
vim.keymap.set("n", "[a", "<cmd>AerialPrev<CR>", { desc = "Previous symbol" })
vim.keymap.set("n", "]a", "<cmd>AerialNext<CR>", { desc = "Next symbol" })

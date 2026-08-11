-- Aerial: code outline (symbols).

return {
  {
    "stevearc/aerial.nvim",
    event = "BufReadPost",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-tree/nvim-web-devicons",
    },
    opts = {
      attach_mode = "global",
      backends = { "lsp", "treesitter", "markdown", "man" },
      show_guides = true,
      layout = { min_width = 28, default_direction = "prefer_right" },
      close_on_select = true,
    },
    keys = {
      { "<leader>at", "<cmd>AerialToggle!<CR>", desc = "Toggle outline" },
      { "[a", "<cmd>AerialPrev<CR>", desc = "Previous symbol" },
      { "]a", "<cmd>AerialNext<CR>", desc = "Next symbol" },
    },
  },
}

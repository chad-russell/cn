local wk = require("which-key")

wk.setup({
  preset = "classic",
  plugins = {
    spelling = { enabled = true },
    presets = {
      operators = true,
      motions = true,
      text_objects = true,
      windows = true,
      nav = true,
      z = true,
      g = true,
    },
  },
})

wk.add({
  { "<leader>b", group = "buffer" },
  { "<leader>s", group = "search" },
  { "<leader>k", desc = "Neo-tree" },
  { "<leader>x", desc = "Close buffer" },
  { "<leader>p", desc = "Paste without yanking", mode = "x" },
  { "<leader>y", desc = "Yank to clipboard", mode = { "n", "v" } },
  { "<leader>d", desc = "Delete without yanking", mode = { "n", "v" } },
  { "<leader>?", desc = "Which-key (buffer local)" },
})

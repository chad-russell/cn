-- Which-key: keymap discovery + group labels (v3).
-- v3 auto-detects keymaps that have a `desc`; the spec below only adds group
-- labels and the buffer-local `<leader>?` picker.

return {
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
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
      spec = {
        { "<leader>a", group = "aerial" },
        { "<leader>b", group = "buffer" },
        { "<leader>c", group = "code" },
        { "<leader>g", group = "git" },
        { "<leader>gh", group = "hunks" },
        { "<leader>q", group = "session" },
        { "<leader>s", group = "search" },
        { "<leader>x", group = "trouble" },
      },
    },
    keys = {
      {
        "<leader>?",
        function()
          local ok, wk = pcall(require, "which-key")
          if ok then wk.show({ global = false }) end
        end,
        desc = "Which-key (buffer local)",
        silent = true,
      },
    },
  },
}

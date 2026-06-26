-- Colorscheme: everforest (lua port). Loaded early (priority 1000).

return {
  {
    "neanias/everforest-nvim",
    version = false,
    lazy = false,
    priority = 1000,
    opts = {
      background = "hard",
      italics = true, -- enable_italic
    },
    config = function(_, opts)
      require("everforest").setup(opts)
      vim.cmd.colorscheme("everforest")
    end,
  },
}

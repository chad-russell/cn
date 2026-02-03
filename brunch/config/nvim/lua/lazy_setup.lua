-- Bootstrap lazy.nvim plugin manager
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

if not vim.loop.fs_stat(lazypath) then
  print("Installing lazy.nvim...")
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end

vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    -- Plugin manager and colorschemes
    {
      "catppuccin/nvim",
      name = "catppuccin",
      priority = 1000, -- Load first
    },

    -- Icons
    {
      "nvim-tree/nvim-web-devicons",
      name = "nvim-web-devicons",
      priority = 999,
    },

    -- File explorer
    {
      "nvim-neo-tree/neo-tree.nvim",
      name = "neo-tree",
      dependencies = {
        "nvim-tree/nvim-web-devicons",
        "MunifTanjim/nui.nvim",
      },
      config = function()
        require("plugins.neo-tree")
      end,
    },

    -- Fuzzy finder
    {
      "nvim-telescope/telescope.nvim",
      name = "telescope",
      dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-telescope/telescope-fzf-native.nvim",
      },
      config = function()
        require("plugins.telescope")
      end,
    },

    -- Syntax highlighting
    {
      "nvim-treesitter/nvim-treesitter",
      name = "nvim-treesitter",
      build = ":TSUpdate",
      event = { "BufReadPost", "BufNewFile" },
      config = function()
        require("plugins.treesitter")
      end,
    },

    -- Status line
    {
      "itchyny/lightline.vim",
      name = "lightline",
    },

    {
      "folke/which-key.nvim",
      name = "which-key",
      event = "VeryLazy",
      config = function()
        require("plugins.which-key")
      end,
    },
  },
  git = {
    url_format = vim.env.GITHUB_TOKEN
      and ("https://x-access-token:" .. vim.env.GITHUB_TOKEN .. "@github.com/%s.git")
      or "https://github.com/%s.git",
  },
})

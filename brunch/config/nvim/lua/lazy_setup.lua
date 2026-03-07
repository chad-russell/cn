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
    -- Colorscheme
    {
      "sainnhe/everforest",
      name = "everforest",
      lazy = false,
      priority = 1000,
      config = function()
        vim.g.everforest_enable_italic = true
        vim.g.everforest_better_performance = true
        vim.g.everforest_background = "hard"
        vim.cmd.colorscheme("everforest")
      end,
    },

    -- Icons
    {
      "nvim-tree/nvim-web-devicons",
      name = "nvim-web-devicons",
      priority = 999,
    },

    -- Mason: Portable package manager for LSP servers
    {
      "williamboman/mason.nvim",
      name = "mason",
      build = ":MasonUpdate",
      config = function()
        require("mason").setup({
          ui = {
            border = "rounded",
            icons = {
              package_installed = "✓",
              package_pending = "➜",
              package_uninstalled = "✗",
            },
          },
        })
      end,
    },

    -- Mason-lspconfig bridge
    {
      "williamboman/mason-lspconfig.nvim",
      name = "mason-lspconfig",
      dependencies = { "mason" },
    },

    -- LSP configuration
    {
      "neovim/nvim-lspconfig",
      name = "nvim-lspconfig",
      dependencies = {
        "mason",
        "mason-lspconfig",
        "hrsh7th/cmp-nvim-lsp",
      },
      config = function()
        require("plugins.lsp")
      end,
    },

    -- Autocompletion
    {
      "hrsh7th/nvim-cmp",
      name = "nvim-cmp",
      event = "InsertEnter",
      dependencies = {
        "hrsh7th/cmp-nvim-lsp",
        "hrsh7th/cmp-buffer",
        "hrsh7th/cmp-path",
        "L3MON4D3/LuaSnip",
        "saadparwaiz1/cmp_luasnip",
        "rafamadriz/friendly-snippets",
      },
      config = function()
        require("plugins.cmp")
      end,
    },

    -- Snippet engine
    {
      "L3MON4D3/LuaSnip",
      name = "LuaSnip",
      build = "make install_jsregexp",
    },

    -- Code formatting
    {
      "stevearc/conform.nvim",
      name = "conform",
      event = "BufWritePre",
      config = function()
        require("plugins.conform")
      end,
    },

    -- Diagnostics list
    {
      "folke/trouble.nvim",
      name = "trouble",
      dependencies = { "nvim-web-devicons" },
      cmd = { "TroubleToggle", "Trouble" },
      config = function()
        require("plugins.trouble")
      end,
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

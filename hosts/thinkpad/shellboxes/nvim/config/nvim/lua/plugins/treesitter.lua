-- Treesitter: highlighting + indent.
-- Uses the archived `master` branch (stable API) with config/treesitter.lua
-- applied as `init` to fix the Neovim 0.12 predicate/query bugs BEFORE the
-- plugin compiles its queries. Parsers auto-install on first launch.

return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "master",
    lazy = false, -- highlight should be available immediately
    build = ":TSUpdate",
    init = function()
      require("config.treesitter")
    end,
    opts = {
      ensure_installed = {
        "lua", "luadoc", "vim", "vimdoc", "query",
        "markdown", "markdown_inline",
        "javascript", "typescript", "tsx",
        "python", "rust", "go",
        "json", "jsonc", "yaml", "toml",
        "html", "css", "bash", "regex",
      },
      highlight = { enable = true },
      indent = { enable = true },
    },
    config = function(_, opts)
      require("nvim-treesitter.configs").setup(opts)
    end,
  },
}

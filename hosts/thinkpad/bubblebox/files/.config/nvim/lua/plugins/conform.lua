-- Formatting (conform.nvim). Formatter binaries must be on $PATH in the
-- image (prettier, stylua, ruff). Falls back to LSP formatting if the
-- filetype formatter is unavailable.

return {
  {
    "stevearc/conform.nvim",
    event = "BufReadPost",
    keys = {
      { "<leader>cf", function() require("conform").format({ lsp_fallback = true }) end, mode = { "n", "v" }, desc = "Format code" },
    },
    opts = {
      formatters_by_ft = {
        javascript = { "prettier" },
        javascriptreact = { "prettier" },
        typescript = { "prettier" },
        typescriptreact = { "prettier" },
        json = { "prettier" },
        jsonc = { "prettier" },
        html = { "prettier" },
        css = { "prettier" },
        markdown = { "prettier" },
        yaml = { "prettier" },
        python = { "ruff_format", "ruff_fix" },
        lua = { "stylua" },
        rust = { "rustfmt" },
      },
      format_on_save = { timeout_ms = 500, lsp_fallback = true },
      format_after_save = { lsp_fallback = true },
    },
  },
}

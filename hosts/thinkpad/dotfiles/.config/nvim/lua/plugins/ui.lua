-- UI: icons + bufferline (VSCode-like tabs).

return {
  { "nvim-tree/nvim-web-devicons", lazy = true, opts = {} },

  {
    "akinsho/bufferline.nvim",
    version = "*",
    event = "BufReadPost",
    dependencies = "nvim-tree/nvim-web-devicons",
    opts = {
      options = {
        mode = "buffers",
        separator_style = "thin",
        always_show_bufferline = true,
        show_buffer_close_icons = true,
        show_close_icon = false,
        diagnostics = "nvim_lsp",
        offsets = {
          {
            filetype = "neo-tree",
            text = "File Explorer",
            highlight = "Directory",
            text_align = "left",
          },
        },
      },
    },
  },
}

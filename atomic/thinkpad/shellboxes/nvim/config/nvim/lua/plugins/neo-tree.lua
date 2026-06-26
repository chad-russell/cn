-- Neo-tree: file explorer (replaces netrw).

return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    cmd = "Neotree",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    opts = {
      filesystem = {
        follow_current_file = { enabled = true },
        use_libuv_file_watcher = true,
      },
    },
    keys = {
      { "<leader>k", "<cmd>Neotree toggle reveal<CR>", desc = "Toggle NeoTree", silent = true },
    },
  },
}

{ ... }:

{
  # Neo-tree is a Neovim plugin to browse the file system
  # https://nix-community.github.io/nixvim/plugins/neo-tree/index.html?highlight=neo-tree#pluginsneo-treepackage
  programs.nixvim.plugins.neo-tree = {
    enable = true;
    autoLoad = true;
  };

  # https://nix-community.github.io/nixvim/keymaps/index.html
  programs.nixvim.keymaps = [
    {
      mode = "n";
      key = "<leader>k";
      action = "<cmd>Neotree toggle<cr>";
      options = {
        desc = "Toggle NeoTree";
        silent = true;
      };
    }
  ];
}

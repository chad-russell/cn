{ config, pkgs, ... }:

{
  imports = [
    ./neo-tree.nix
    ./telescope.nix
  ];

  programs.nixvim = {
    enable = true;
    defaultEditor = true;

    colorschemes.catppuccin.enable = true;

    opts = {
      # Cursor
      guicursor = "n-v-c:block,i-ci-ve:ver25,r-cr:hor20,o:hor50";

      # Line numbers
      number = true;
      relativenumber = true;

      # Indentation and tabs
      tabstop = 4;
      softtabstop = 4;
      shiftwidth = 4;
      expandtab = true;
      smartindent = true;

      # Text display
      wrap = false;
      cursorline = true;

      # File handling
      swapfile = false;
      backup = false;
      undofile = true;
      undodir = "${config.home.homeDirectory}/.vim/undodir";

      # Search
      hlsearch = false;
      incsearch = true;
      ignorecase = true;

      # Display
      termguicolors = true;
      scrolloff = 8;
      signcolumn = "yes";
      cmdheight = 1;

      # Performance and timing
      updatetime = 50;
      timeoutlen = 1000;
      ttimeoutlen = 0;

      # Command preview
      inccommand = "split";
    };

    globals = {
      mapleader = " ";
      maplocalleader = " ";
      have_nerd_font = true;
      loaded_netrw = 1;
      loaded_netrwPlugin = 1;
    };

    plugins = {
      lightline = {
        enable = true; # Simple status line
      };
      treesitter = {
        enable = true;
      };
    };

    keymaps = [
      # Command mode
      {
        mode = "n";
        key = ";";
        action = ":";
        options = {
          desc = "CMD enter command mode";
          noremap = true;
        };
      }

      # Scrolling with centering
      {
        mode = "n";
        key = "<C-d>";
        action = "<C-d>zz";
        options = {
          desc = "Scroll down and center";
        };
      }
      {
        mode = "n";
        key = "<C-u>";
        action = "<C-u>zz";
        options = {
          desc = "Scroll up and center";
        };
      }

      # Search navigation with centering
      {
        mode = "n";
        key = "n";
        action = "nzzzv";
        options = {
          desc = "Next search result and center";
        };
      }
      {
        mode = "n";
        key = "N";
        action = "Nzzzv";
        options = {
          desc = "Previous search result and center";
        };
      }

      # Join lines
      {
        mode = "n";
        key = "J";
        action = "mzJ`z";
        options = {
          desc = "Join lines and maintain cursor position";
        };
      }

      # Yank to end of line
      {
        mode = "n";
        key = "Y";
        action = "yg$";
        options = {
          desc = "Yank to end of line";
        };
      }

      # Movement remaps
      {
        mode = "";
        key = "L";
        action = "$";
        options = {
          desc = "Move to end of line";
        };
      }
      {
        mode = "";
        key = "H";
        action = "^";
        options = {
          desc = "Move to start of line";
        };
      }
      {
        mode = "";
        key = "K";
        action = "%";
        options = {
          desc = "Jump to matching bracket";
        };
      }

      # Disable original movement keys
      {
        mode = "";
        key = "$";
        action = "<nop>";
      }
      {
        mode = "";
        key = "^";
        action = "<nop>";
      }
      {
        mode = "";
        key = "%";
        action = "<nop>";
      }

      # Buffer navigation
      {
        mode = "n";
        key = "<tab>";
        action = "<cmd>bnext<CR>";
        options = {
          desc = "Next buffer";
        };
      }
      {
        mode = "n";
        key = "<S-tab>";
        action = "<cmd>bprev<CR>";
        options = {
          desc = "Previous buffer";
        };
      }
      {
        mode = "n";
        key = "<leader>x";
        action = "<cmd>bdelete<CR>";
        options = {
          desc = "Close buffer";
        };
      }

      # Paste without yanking
      {
        mode = "x";
        key = "<leader>p";
        action = "\"_dP";
        options = {
          desc = "Paste without yanking";
        };
      }

      # Yank to system clipboard
      {
        mode = [ "n" "v" ];
        key = "<leader>y";
        action = "\"+y";
        options = {
          desc = "Yank to system clipboard";
        };
      }

      # Delete without yanking
      {
        mode = [ "n" "v" ];
        key = "<leader>d";
        action = "\"_d";
        options = {
          desc = "Delete without yanking";
        };
      }

      # Disable Q
      {
        mode = "n";
        key = "Q";
        action = "<nop>";
      }

      # Window navigation
      {
        mode = "n";
        key = "<C-h>";
        action = "<C-w><C-h>";
        options = {
          desc = "Move focus to the left";
        };
      }
      {
        mode = "n";
        key = "<C-l>";
        action = "<C-w><C-l>";
        options = {
          desc = "Move focus to the right";
        };
      }
      {
        mode = "n";
        key = "<C-j>";
        action = "<C-w><C-j>";
        options = {
          desc = "Move focus down";
        };
      }
      {
        mode = "n";
        key = "<C-k>";
        action = "<C-w><C-k>";
        options = {
          desc = "Move focus up";
        };
      }

      # Which-key show
      {
        mode = "n";
        key = "<leader>?";
        action = ":lua require('which-key').show({ global = false })<CR>";
        options = {
          desc = "Show which-key mappings";
          silent = true;
        };
      }
    ];
  };
}

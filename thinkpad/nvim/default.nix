{
  config,
  pkgs,
  lib,
  ...
}:
{
  programs.nixvim = {
    enable = true;

    # Use the same leader keys as your old config
    globals = {
      mapleader = " ";
      maplocalleader = " ";
      loaded_netrw = 1;
      loaded_netrwPlugin = 1;
      loaded_node_provider = 0;
      loaded_perl_provider = 0;
      loaded_python3_provider = 0;
      loaded_ruby_provider = 0;
    };

    # Disable netrw (neo-tree replaces it)
    performance = {
      byteCompileLua = {
        enable = true;
        nvimRuntime = true;
        configs = true;
        plugins = true;
      };
    };

    # =====================================================================
    # Colorscheme
    # =====================================================================
    colorschemes.everforest = {
      enable = true;
      settings = {
        background = "hard";
        enable_italic = 1;
        better_performance = 1;
      };
    };

    # =====================================================================
    # Options (from lua/options.lua)
    # =====================================================================
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

      # Search
      hlsearch = false;
      incsearch = true;
      ignorecase = true;

      # Display
      termguicolors = true;
      scrolloff = 8;
      signcolumn = "yes";
      cmdheight = 1;
      showtabline = 2;

      # Performance and timing
      updatetime = 50;
      timeoutlen = 1000;
      ttimeoutlen = 0;

      # Command preview
      inccommand = "split";

      # Native completion (Neovim 0.12)
      completeopt = [ "menuone" "noselect" "popup" ];
      autocomplete = true;
      pumborder = "rounded";


    };

    # =====================================================================
    # Keymaps (from lua/keymaps.lua)
    # =====================================================================
    keymaps = [
      # Command mode
      { key = ";"; action = ":"; mode = "n"; options.desc = "CMD enter command mode"; options.noremap = true; }

      # Scrolling with centering
      { key = "<C-d>"; action = "<C-d>zz"; mode = "n"; options.desc = "Scroll down and center"; }
      { key = "<C-u>"; action = "<C-u>zz"; mode = "n"; options.desc = "Scroll up and center"; }

      # Search navigation with centering
      { key = "n"; action = "nzzzv"; mode = "n"; options.desc = "Next search result and center"; }
      { key = "N"; action = "Nzzzv"; mode = "n"; options.desc = "Previous search result and center"; }

      # Join lines
      { key = "J"; action = "mzJ`z"; mode = "n"; options.desc = "Join lines and maintain cursor position"; }

      # Yank to end of line
      { key = "Y"; action = "yg$"; mode = "n"; options.desc = "Yank to end of line"; }

      # Movement remaps: L/H for end/start of line
      { key = "L"; action = "$"; mode = [ "n" "v" ]; options.desc = "Move to end of line"; }
      { key = "H"; action = "^"; mode = [ "n" "v" ]; options.desc = "Move to start of line"; }

      # Jump to matching bracket
      { key = "\\"; action = "%"; mode = [ "n" "v" ]; options.desc = "Jump to matching bracket"; }

      # Disable original movement keys
      { key = "$"; action = "<nop>"; mode = [ "n" "v" ]; options.desc = "Disabled: use L instead"; }
      { key = "^"; action = "<nop>"; mode = [ "n" "v" ]; options.desc = "Disabled: use H instead"; }
      { key = "%"; action = "<nop>"; mode = [ "n" "v" ]; options.desc = "Disabled: use \\ instead"; }

      # Buffer navigation
      { key = "<tab>"; action = "<cmd>bnext<CR>"; mode = "n"; options.desc = "Next buffer"; }
      { key = "<S-tab>"; action = "<cmd>bprev<CR>"; mode = "n"; options.desc = "Previous buffer"; }
      { key = "<leader>x"; action = "<cmd>bdelete<CR>"; mode = "n"; options.desc = "Close buffer"; }

      # Paste without yanking
      { key = "<leader>p"; action = "\"_dP"; mode = "x"; options.desc = "Paste without yanking"; }

      # Yank to system clipboard
      { key = "<leader>y"; action = "\"+y"; mode = [ "n" "v" ]; options.desc = "Yank to system clipboard"; }

      # Delete without yanking
      { key = "<leader>d"; action = "\"_d"; mode = [ "n" "v" ]; options.desc = "Delete without yanking"; }

      # Disable Q
      { key = "Q"; action = "<nop>"; mode = "n"; options.desc = "Disabled: Ex mode"; }

      # Window navigation
      { key = "<C-h>"; action = "<C-w><C-h>"; mode = "n"; options.desc = "Move focus to the left"; }
      { key = "<C-l>"; action = "<C-w><C-l>"; mode = "n"; options.desc = "Move focus to the right"; }
      { key = "<C-j>"; action = "<C-w><C-j>"; mode = "n"; options.desc = "Move focus down"; }
      { key = "<C-k>"; action = "<C-w><C-k>"; mode = "n"; options.desc = "Move focus up"; }

      # Neo-tree
      { key = "<leader>k"; action = "<cmd>Neotree toggle reveal<cr>"; mode = "n"; options.desc = "Toggle NeoTree"; options.silent = true; }

      # Aerial (code outline)
      { key = "<leader>at"; action = "<cmd>AerialToggle!<CR>"; mode = "n"; options.desc = "Toggle outline"; }
      { key = "[a"; action = "<cmd>AerialPrev<CR>"; mode = "n"; options.desc = "Previous symbol"; }
      { key = "]a"; action = "<cmd>AerialNext<CR>"; mode = "n"; options.desc = "Next symbol"; }

      # Trouble
      { key = "<leader>xx"; mode = "n"; options.desc = "Toggle trouble"; action.__raw = ''function() require("trouble").toggle() end''; }
      { key = "<leader>xw"; mode = "n"; options.desc = "Workspace diagnostics"; action.__raw = ''function() require("trouble").toggle("workspace_diagnostics") end''; }
      { key = "<leader>xd"; mode = "n"; options.desc = "Document diagnostics"; action.__raw = ''function() require("trouble").toggle("document_diagnostics") end''; }
      { key = "<leader>xq"; mode = "n"; options.desc = "Quickfix list"; action.__raw = ''function() require("trouble").toggle("quickfix") end''; }
      { key = "<leader>xl"; mode = "n"; options.desc = "Location list"; action.__raw = ''function() require("trouble").toggle("loclist") end''; }
      { key = "gR"; mode = "n"; options.desc = "LSP references (trouble)"; action.__raw = ''function() require("trouble").toggle("lsp_references") end''; }

      # Flash
      { key = "s"; mode = [ "n" "x" "o" ]; options.desc = "Flash"; action.__raw = ''function() require("flash").jump() end''; }
      { key = "S"; mode = [ "n" "x" "o" ]; options.desc = "Flash Treesitter"; action.__raw = ''function() require("flash").treesitter() end''; }
      { key = "r"; mode = "o"; options.desc = "Remote Flash"; action.__raw = ''function() require("flash").remote() end''; }
      { key = "R"; mode = [ "o" "x" ]; options.desc = "Treesitter Search"; action.__raw = ''function() require("flash").treesitter_search() end''; }

      # Conform (format)
      { key = "<leader>cf"; mode = [ "n" "v" ]; options.desc = "Format code"; action.__raw = ''function() require("conform").format({ lsp_fallback = true }) end''; }

      # Persistence (sessions)
      { key = "<leader>qs"; mode = "n"; options.desc = "Restore session"; action.__raw = ''function() require("persistence").load() end''; }
      { key = "<leader>ql"; mode = "n"; options.desc = "Restore last session"; action.__raw = ''function() require("persistence").load({ last = true }) end''; }
      { key = "<leader>qd"; mode = "n"; options.desc = "Stop saving session"; action.__raw = ''function() require("persistence").stop() end''; }

      # Telescope
      { key = "<leader>sh"; mode = "n"; options.desc = "[S]earch [H]elp"; action.__raw = ''function() require("telescope.builtin").help_tags() end''; }
      { key = "<leader>sk"; mode = "n"; options.desc = "[S]earch [K]eymaps"; action.__raw = ''function() require("telescope.builtin").keymaps() end''; }
      { key = "<leader>sf"; mode = "n"; options.desc = "[S]earch [F]iles"; action.__raw = ''function() require("telescope.builtin").find_files() end''; }
      { key = "<leader>ss"; mode = "n"; options.desc = "[S]earch [S]elect Telescope"; action.__raw = ''function() require("telescope.builtin").builtin() end''; }
      { key = "<leader>sw"; mode = "n"; options.desc = "[S]earch current [W]ord"; action.__raw = ''function() require("telescope.builtin").grep_string() end''; }
      { key = "<leader>sg"; mode = "n"; options.desc = "[S]earch by [G]rep"; action.__raw = ''function() require("telescope.builtin").live_grep() end''; }
      { key = "<leader>sd"; mode = "n"; options.desc = "[S]earch [D]iagnostics"; action.__raw = ''function() require("telescope.builtin").diagnostics() end''; }
      { key = "<leader>sr"; mode = "n"; options.desc = "[S]earch [R]esume"; action.__raw = ''function() require("telescope.builtin").resume() end''; }
      { key = "<leader>s."; mode = "n"; options.desc = "[S]earch Recent Files ('.' for repeat)"; action.__raw = ''function() require("telescope.builtin").oldfiles() end''; }
      { key = "<leader><leader>"; mode = "n"; options.desc = "[ ] Find existing buffers"; action.__raw = ''function() require("telescope.builtin").buffers() end''; }
      { key = "<leader>/"; mode = "n"; options.desc = "[/] Fuzzily search in current buffer"; action.__raw = ''
        function()
          require("telescope.builtin").current_buffer_fuzzy_find(
            require("telescope.themes").get_dropdown({
              winblend = 10,
              previewer = false
            })
          )
        end
      ''; }
      { key = "<leader>s/"; mode = "n"; options.desc = "[S]earch [/] in Open Files"; action.__raw = ''
        function()
          require("telescope.builtin").live_grep({
            grep_open_files = true,
            prompt_title = 'Live Grep in Open Files'
          })
        end
      ''; }
      { key = "<leader>sn"; mode = "n"; options.desc = "[S]earch [N]eovim files"; action.__raw = ''
        function()
          require("telescope.builtin").find_files({ cwd = vim.fn.stdpath('config') })
        end
      ''; }

      # Snippet jumping
      { key = "<C-n>"; mode = [ "i" "s" ]; options.desc = "Snippet jump forward"; options.expr = true; action.__raw = ''
        function()
          if vim.snippet.active({ direction = 1 }) then
            vim.snippet.jump(1)
            return
          end
          return "<C-n>"
        end
      ''; }
      { key = "<C-p>"; mode = [ "i" "s" ]; options.desc = "Snippet jump backward"; options.expr = true; action.__raw = ''
        function()
          if vim.snippet.active({ direction = -1 }) then
            vim.snippet.jump(-1)
            return
          end
          return "<C-p>"
        end
      ''; }

      # Which-key (buffer local)
      { key = "<leader>?"; mode = "n"; options.desc = "Which-key (buffer local)"; options.silent = true; action.__raw = ''
        function()
          local ok, wk = pcall(require, 'which-key')
          if ok then wk.show({ global = false }) end
        end
      ''; }
    ];

    # =====================================================================
    # Plugins
    # =====================================================================

    # --- Icons ---
    plugins.web-devicons.enable = true;

    # --- Bufferline (VSCode-like tabs) ---
    plugins.bufferline = {
      enable = true;
      settings = {
        options = {
          mode = "buffers";
          separator_style = "thin";
          always_show_bufferline = true;
          show_buffer_close_icons = true;
          show_close_icon = false;
          diagnostics = "nvim_lsp";
          offsets = [
            {
              filetype = "neo-tree";
              text = "File Explorer";
              highlight = "Directory";
              text_align = "left";
            }
          ];
        };
      };
    };

    # --- Comment ---
    plugins.comment.enable = true;

    # --- Conform (formatting) ---
    plugins.conform-nvim = {
      enable = true;
      settings = {
        formatters_by_ft = {
          javascript = [ "prettier" ];
          javascriptreact = [ "prettier" ];
          typescript = [ "prettier" ];
          typescriptreact = [ "prettier" ];
          json = [ "prettier" ];
          jsonc = [ "prettier" ];
          html = [ "prettier" ];
          css = [ "prettier" ];
          markdown = [ "prettier" ];
          yaml = [ "prettier" ];
          python = [ "ruff_format" "ruff_fix" ];
          lua = [ "stylua" ];
          rust = [ "rustfmt" ];
        };
        format_on_save = {
          timeout_ms = 500;
          lsp_fallback = true;
        };
        format_after_save = {
          lsp_fallback = true;
        };
      };
    };

    # --- Flash (navigation) ---
    plugins.flash.enable = true;

    # --- Gitsigns ---
    plugins.gitsigns = {
      enable = true;
      settings = {
        signs = {
          add = { text = "+"; };
          change = { text = "~"; };
          delete = { text = "_"; };
          topdelete = { text = "‾"; };
          changedelete = { text = "~"; };
        };
        current_line_blame = false;
        on_attach = /* lua */ ''
          function(bufnr)
            local gs = package.loaded.gitsigns

            local function map(mode, lhs, rhs, desc)
              vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc, silent = true })
            end

            map("n", "]h", function()
              if vim.wo.diff then
                vim.cmd.normal({ "]h", bang = true })
              else
                gs.nav_hunk("next")
              end
            end, "Next hunk")

            map("n", "[h", function()
              if vim.wo.diff then
                vim.cmd.normal({ "[h", bang = true })
              else
                gs.nav_hunk("prev")
              end
            end, "Previous hunk")

            map("n", "<leader>ghs", gs.stage_hunk, "Stage hunk")
            map("n", "<leader>ghr", gs.reset_hunk, "Reset hunk")
            map("v", "<leader>ghs", function()
              gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
            end, "Stage hunk")
            map("v", "<leader>ghr", function()
              gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
            end, "Reset hunk")
            map("n", "<leader>ghS", gs.stage_buffer, "Stage buffer")
            map("n", "<leader>ghu", gs.undo_stage_hunk, "Undo stage hunk")
            map("n", "<leader>ghR", gs.reset_buffer, "Reset buffer")
            map("n", "<leader>ghp", gs.preview_hunk, "Preview hunk")
            map("n", "<leader>ghb", function()
              gs.blame_line({ full = true })
            end, "Blame line")
            map("n", "<leader>ghd", gs.diffthis, "Diff this")
            map("n", "<leader>ghD", function()
              gs.diffthis("~")
            end, "Diff this ~")
            map("n", "<leader>ght", gs.toggle_current_line_blame, "Toggle line blame")
            map("n", "<leader>ghT", gs.toggle_deleted, "Toggle deleted")
            map({ "o", "x" }, "ih", gs.select_hunk, "Select hunk")
          end
        '';
      };
    };

    # --- Aerial (code outline) ---
    plugins.aerial = {
      enable = true;
      settings = {
        attach_mode = "global";
        backends = [ "lsp" "treesitter" "markdown" "man" ];
        show_guides = true;
        layout = {
          min_width = 28;
          default_direction = "prefer_right";
        };
        close_on_select = true;
      };
    };

    # --- Persistence (sessions) ---
    plugins.persistence = {
      enable = true;
      options = [ "buffers" "curdir" "tabpages" "winsize" "help" "globals" "skiprtp" ];
    };

    # --- Neo-tree (file explorer) ---
    plugins.neo-tree = {
      enable = true;
    };

    # --- Telescope ---
    plugins.telescope = {
      enable = true;
      settings = {
        defaults = {
          mappings = {
            i = {
              "<C-/>" = "which_key";
            };
            n = {
              "?" = "which_key";
            };
          };
        };
        extensions = {
          fzf = {
            fuzzy = true;
            override_generic_sorter = true;
          };
        };
      };
      extensions.fzf-native = {
        enable = true;
        settings = {
          fuzzy = true;
          override_generic_sorter = true;
          override_file_sorter = true;
          case_mode = "smart_case";
        };
      };
    };

    # --- Treesitter ---
    plugins.treesitter = {
      enable = true;
      settings = {
        highlight = {
          enable = true;
        };
        indent = {
          enable = true;
        };
      };
    };

    # --- Trouble (diagnostics list) ---
    plugins.trouble = {
      enable = true;
      settings = { };
    };

    # --- Which-key ---
    plugins.which-key = {
      enable = true;
      settings = {
        preset = "classic";
        plugins = {
          spelling = { enabled = true; };
          presets = {
            operators = true;
            motions = true;
            text_objects = true;
            windows = true;
            nav = true;
            z = true;
            g = true;
          };
        };
        spec = [
          { __unkeyed = "<leader>a"; group = "aerial"; }
          { __unkeyed = "<leader>at"; desc = "Toggle outline"; }
          { __unkeyed = "<leader>b"; group = "buffer"; }
          { __unkeyed = "<tab>"; desc = "Next buffer"; }
          { __unkeyed = "<S-tab>"; desc = "Previous buffer"; }
          { __unkeyed = "<leader>c"; group = "code"; }
          { __unkeyed = "<leader>g"; group = "git"; }
          { __unkeyed = "<leader>gh"; group = "hunks"; }
          { __unkeyed = "<leader>ghs"; desc = "Stage hunk"; mode = [ "n" "v" ]; }
          { __unkeyed = "<leader>ghr"; desc = "Reset hunk"; mode = [ "n" "v" ]; }
          { __unkeyed = "<leader>ghS"; desc = "Stage buffer"; }
          { __unkeyed = "<leader>ghu"; desc = "Undo stage hunk"; }
          { __unkeyed = "<leader>ghR"; desc = "Reset buffer"; }
          { __unkeyed = "<leader>ghp"; desc = "Preview hunk"; }
          { __unkeyed = "<leader>ghb"; desc = "Blame line"; }
          { __unkeyed = "<leader>ghd"; desc = "Diff this"; }
          { __unkeyed = "<leader>ghD"; desc = "Diff this ~"; }
          { __unkeyed = "<leader>ght"; desc = "Toggle line blame"; }
          { __unkeyed = "<leader>ghT"; desc = "Toggle deleted"; }
          { __unkeyed = "<leader>q"; group = "session"; }
          { __unkeyed = "<leader>qs"; desc = "Restore session"; }
          { __unkeyed = "<leader>ql"; desc = "Restore last session"; }
          { __unkeyed = "<leader>qd"; desc = "Stop saving session"; }
          { __unkeyed = "<leader>s"; group = "search"; }
          { __unkeyed = "<leader>k"; desc = "Neo-tree"; }
          { __unkeyed = "<leader>x"; desc = "Close buffer"; }
          { __unkeyed = "<leader>p"; desc = "Paste without yanking"; mode = "x"; }
          { __unkeyed = "<leader>y"; desc = "Yank to clipboard"; mode = [ "n" "v" ]; }
          { __unkeyed = "<leader>d"; desc = "Delete without yanking"; mode = [ "n" "v" ]; }
          { __unkeyed = "<leader>?"; desc = "Which-key (buffer local)"; }
        ];
      };
    };

    # =====================================================================
    # Extra Lua config (LSP setup, diagnostics, etc.)
    # =====================================================================
    extraConfigLua = ''
      -- Speed up Lua module loading
      vim.loader.enable()

      -- Nerd font support
      vim.g.have_nerd_font = true

      -- ================================================================
      -- LSP Configuration (using native vim.lsp.config + vim.lsp.enable)
      -- ================================================================

      -- Custom LSP keymaps on attach
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("UserLspConfig", {}),
        callback = function(ev)
          local opts = { buffer = ev.buf, silent = true }
          local keymap = vim.keymap.set

          keymap("n", "gD", vim.lsp.buf.declaration, vim.tbl_extend("force", opts, { desc = "Go to declaration" }))
          keymap("n", "gd", vim.lsp.buf.definition, vim.tbl_extend("force", opts, { desc = "Go to definition" }))
          keymap("n", "<leader>wa", vim.lsp.buf.add_workspace_folder, vim.tbl_extend("force", opts, { desc = "Add workspace folder" }))
          keymap("n", "<leader>wr", vim.lsp.buf.remove_workspace_folder, vim.tbl_extend("force", opts, { desc = "Remove workspace folder" }))
          keymap("n", "<leader>wl", function()
            print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
          end, vim.tbl_extend("force", opts, { desc = "List workspace folders" }))
          keymap("n", "<leader>f", function()
            vim.lsp.buf.format({ async = true })
          end, vim.tbl_extend("force", opts, { desc = "Format buffer" }))

          -- Enable LSP-driven autocompletion for this buffer
          vim.lsp.completion.enable(true, ev.data.client_id, ev.buf, {
            autotrigger = true,
          })
        end,
      })

      -- Diagnostic configuration
      vim.diagnostic.config({
        virtual_text = {
          prefix = "●",
          spacing = 4,
        },
        signs = true,
        underline = true,
        update_in_insert = false,
        severity_sort = true,
        float = {
          border = "rounded",
          source = "always",
        },
      })

      -- Show line diagnostics on hover
      vim.api.nvim_create_autocmd("CursorHold", {
        callback = function()
          vim.diagnostic.open_float(nil, { focus = false })
        end,
      })

      -- Server configurations using vim.lsp.config
      vim.lsp.config.ts_ls = {
        cmd = { "typescript-language-server", "--stdio" },
        filetypes = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
        root_markers = { "tsconfig.json", "jsconfig.json", "package.json", ".git" },
        settings = {
          typescript = {
            inlayHints = {
              includeInlayParameterNameHints = "all",
              includeInlayParameterNameHintsWhenArgumentMatchesName = false,
              includeInlayFunctionParameterTypeHints = true,
              includeInlayVariableTypeHints = true,
              includeInlayPropertyDeclarationTypeHints = true,
              includeInlayFunctionLikeReturnTypeHints = true,
              includeInlayEnumMemberValueHints = true,
            },
          },
          javascript = {
            inlayHints = {
              includeInlayParameterNameHints = "all",
              includeInlayParameterNameHintsWhenArgumentMatchesName = false,
              includeInlayFunctionParameterTypeHints = true,
              includeInlayVariableTypeHints = true,
              includeInlayPropertyDeclarationTypeHints = true,
              includeInlayFunctionLikeReturnTypeHints = true,
              includeInlayEnumMemberValueHints = true,
            },
          },
        },
      }

      vim.lsp.config.rust_analyzer = {
        cmd = { "rust-analyzer" },
        filetypes = { "rust" },
        root_markers = { "Cargo.toml", "Cargo.lock", ".git" },
        settings = {
          ["rust-analyzer"] = {
            check = { command = "clippy" },
            inlayHints = {
              bindingModeHints = { enable = true },
              chainingHints = { enable = true },
              closingBraceHints = { minLines = 10 },
              closureReturnTypeHints = { enable = "with_block" },
              lifetimeElisionHints = { enable = "skip_trivial", useParameterNames = true },
              parameterHints = { enable = true },
              reborrowHints = { enable = "mutable" },
              renderColons = true,
              typeHints = { enable = true, hideClosureInitialization = false, hideNamedConstructor = false },
            },
            cargo = { allFeatures = true, loadOutDirsFromCheck = true },
            procMacro = { enable = true },
          },
        },
      }

      vim.lsp.config.pyright = {
        cmd = { "pyright-langserver", "--stdio" },
        filetypes = { "python" },
        root_markers = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", "Pipfile", "pyrightconfig.json", ".git" },
        settings = {
          python = {
            analysis = {
              typeCheckingMode = "basic",
              autoSearchPaths = true,
              useLibraryCodeForTypes = true,
              diagnosticMode = "workspace",
            },
          },
        },
      }

      vim.lsp.config.lua_ls = {
        cmd = { "lua-language-server" },
        filetypes = { "lua" },
        root_markers = { ".luarc.json", ".luarc.jsonc", ".luacheckrc", ".stylua.toml", "stylua.toml", "selene.toml", ".git" },
        settings = {
          Lua = {
            diagnostics = { globals = { "vim" } },
            workspace = {
              library = vim.api.nvim_get_runtime_file("", true),
              checkThirdParty = false,
            },
            telemetry = { enable = false },
            hint = { enable = true },
          },
        },
      }

      vim.lsp.config.markdown_oxide = {
        cmd = { "markdown-oxide" },
        filetypes = { "markdown" },
        root_markers = { ".git", ".obsidian" },
        capabilities = {
          workspace = {
            didChangeWatchedFiles = {
              dynamicRegistration = true,
            },
          },
        },
      }

      -- Enable LSP servers
      vim.lsp.enable({
        'ts_ls',
        'rust_analyzer',
        'pyright',
        'lua_ls',
        'markdown_oxide',
      })
    '';

    # =====================================================================
    # Extra packages (LSPs, formatters, etc. — replaces Mason)
    # =====================================================================
    extraPackages = with pkgs; [
      # LSP servers
      typescript-language-server
      rust-analyzer
      pyright
      lua-language-server
      markdown-oxide

      # Formatters
      prettierd
      stylua
      ruff

      # General tools
      ripgrep
      fd
    ];
  };
}

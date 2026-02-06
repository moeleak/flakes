{ pkgs, ... }:

{
  home.packages = with pkgs; [
    nixd
    clang-tools
    nixpkgs-fmt
    ripgrep
    yazi
    statix
    pyright
    black
  ];

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    plugins = with pkgs.vimPlugins; [
      catppuccin-nvim
      nvim-treesitter.withAllGrammars
      gitsigns-nvim
      bufferline-nvim
      lualine-nvim
      nvim-web-devicons
      yazi-nvim
      nvim-autopairs
      conform-nvim

      nvim-cmp
      cmp-nvim-lsp
      cmp-path
      luasnip
      cmp_luasnip
      lspkind-nvim
    ];

    initLua = ''
      -- ================= UI Basics =================
      vim.opt.expandtab = true
      vim.opt.shiftwidth = 2
      vim.opt.tabstop = 2
      vim.opt.number = true
      vim.opt.relativenumber = true
      vim.opt.ignorecase = true
      vim.opt.smartcase = true
      vim.opt.termguicolors = true
      vim.opt.showmode = false 
      vim.opt.cursorline = true
      vim.g.mapleader = " "

      vim.opt.clipboard = "unnamedplus"

      -- [New] Persistent Undo Settings
      -- Saves undo history to disk, allowing undo even after closing and reopening Vim
      vim.opt.undofile = true
      
      -- ================= Theme: Catppuccin =================
      local cat_ok, catppuccin = pcall(require, "catppuccin")
      if cat_ok then
        catppuccin.setup({
          flavour = "mocha",
          transparent_background = true,
          term_colors = true,
          integrations = { cmp = true, gitsigns = true, treesitter = true },
        })
        vim.cmd.colorscheme "catppuccin"
      else
        vim.cmd.colorscheme "default"
      end

      -- ================= Treesitter =================
      local ts_ok, ts_configs = pcall(require, "nvim-treesitter.configs")
      if ts_ok then
        ts_configs.setup {
          highlight = { enable = true, additional_vim_regex_highlighting = false },
          indent = { enable = true },
        }
      end

      -- ================= Gitsigns =================
      local gs_ok, gitsigns = pcall(require, "gitsigns")
      if gs_ok then
        gitsigns.setup {
          signcolumn = false,
          current_line_blame = true,
          current_line_blame_opts = { delay = 300, virt_text_pos = 'eol' },
        }
      end

      -- ================= Bufferline =================
      local bl_ok, bufferline = pcall(require, "bufferline")
      if bl_ok then
        bufferline.setup{
          options = {
            mode = "buffers",
            style_preset = bufferline.style_preset.default,
            separator_style = "thin", 
            indicator = { style = 'none' },
            numbers = "ordinal",
            diagnostics = "nvim_lsp",
            diagnostics_indicator = function(count, level)
              return " " .. (level:match("error") and " " or " ") .. count
            end,
            offsets = {{ filetype = "NvimTree", text = "Explorer", text_align = "left", separator = true }},
            get_element_icon = function(element)
              local icon, hl = require('nvim-web-devicons').get_icon_by_filetype(element.filetype, { default = false })
              return icon, hl
            end,
          }
        }
      end

      -- ================= Lualine =================
      local ll_ok, lualine = pcall(require, "lualine")
      if ll_ok then
        lualine.setup {
          options = {
            theme = 'catppuccin', 
            component_separators = { left = '', right = ''},
            section_separators = { left = '', right = ''},
            globalstatus = true,
          },
          sections = {
            lualine_a = {'mode'},
            lualine_b = {'branch', 'diff', 'diagnostics'},
            lualine_c = {'filename'},
            lualine_x = {'encoding', 'fileformat', 'filetype'},
            lualine_y = {'progress'},
            lualine_z = {'location'}
          },
        }
      end

      -- ================= Functional Initialization =================
      require("nvim-autopairs").setup {}
      require("nvim-web-devicons").setup {}
      
      require("yazi").setup({
        open_for_directories = false,
        keymaps = { show_help = '<f1>' },
        hooks = {
          yazi_opened = function(_, buffer, _)
            vim.keymap.set('t', '<Esc>', '<C-\\><C-n>:close<CR>', { buffer = buffer })
          end,
        },
      })

      require("conform").setup({
        formatters_by_ft = {
          nix = { "nixpkgs_fmt" },
          cpp = { "clang_format" },
          c   = { "clang_format" },
          python = { "black" },
        },
        format_on_save = { timeout_ms = 500, lsp_fallback = true },
      })

      vim.diagnostic.config({
        virtual_text = {
          prefix = '●',
          spacing = 4,
          format = function(diagnostic)
            local max_width = 50 
            local message = diagnostic.message:gsub("\n", " ")
            if #message > max_width then
              return string.sub(message, 1, max_width) .. "..."
            end
            return message
          end,
        },
        underline = true,
        update_in_insert = true,
        severity_sort = true,
        signs = {
          text = {
            [vim.diagnostic.severity.ERROR] = ' ',
            [vim.diagnostic.severity.WARN] = ' ',
            [vim.diagnostic.severity.HINT] = ' ',
            [vim.diagnostic.severity.INFO] = ' ',
          },
        },
      })

      -- ================= CMP Slimming =================
      local cmp = require('cmp')
      local luasnip = require('luasnip')
      local lspkind = require('lspkind') -- Import icon plugin

      cmp.setup({
        snippet = { expand = function(args) luasnip.lsp_expand(args.body) end },
        
        -- [Mod] Limit window height, add border for neatness
        window = {
          completion = cmp.config.window.bordered({
            max_height = 10, -- Max 10 lines
          }),
          documentation = cmp.config.window.bordered(),
        },

        -- [Mod] Use lspkind formatting: show icons instead of text
        formatting = {
          format = lspkind.cmp_format({
            mode = 'symbol', -- Show only icons (symbol) or 'symbol_text' (icon + text)
            maxwidth = 50, 
            ellipsis_char = '...',
          })
        },

        mapping = cmp.mapping.preset.insert({
          ['<C-b>'] = cmp.mapping.scroll_docs(-4),
          ['<C-f>'] = cmp.mapping.scroll_docs(4),
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<CR>'] = cmp.mapping.confirm({ select = true }),
          ['<Tab>'] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.select_next_item() else fallback() end
          end, { 'i', 's' }),
          ['<S-Tab>'] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.select_prev_item() else fallback() end
          end, { 'i', 's' }),
        }),

        -- [Mod] Simplify sources
        sources = cmp.config.sources({
          -- Limit LSP suggestions to 10 items
          { name = 'nvim_lsp', max_item_count = 10 },
          -- Limit Snippet suggestions to 5 items
          { name = 'luasnip', max_item_count = 5 },
        }, {
          -- Removed 'buffer' source to prevent excessive irrelevant words
          { name = 'path' }, -- Keep path completion
        })
      })

      local capabilities = require('cmp_nvim_lsp').default_capabilities()

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "nix",
        callback = function(args)
          local root = vim.fs.dirname(vim.fs.find({'flake.nix', '.git'}, { path = args.file, upward = true })[1] or args.file)
          vim.lsp.start({
            name = "nixd",
            cmd = { "nixd" },
            root_dir = root,
            capabilities = capabilities,
            settings = { nixd = { formatting = { command = { "nixpkgs-fmt" } } } }
          })
        end,
      })

      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "c", "cpp", "objc", "objcpp" },
        callback = function(args)
          local root = vim.fs.dirname(vim.fs.find({'.git', 'compile_commands.json'}, { path = args.file, upward = true })[1] or args.file)
          vim.lsp.start({
            name = "clangd",
            cmd = { "clangd" },
            root_dir = root,
            capabilities = capabilities,
          })
        end,
      })

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "python",
        callback = function(args)
          local root = vim.fs.dirname(vim.fs.find({'pyproject.toml', 'setup.py', 'requirements.txt', '.git'}, { path = args.file, upward = true })[1] or args.file)
          vim.lsp.start({
            name = "pyright",
            cmd = { "pyright-langserver", "--stdio" },
            root_dir = root,
            capabilities = capabilities,
            settings = { python = { analysis = { autoSearchPaths = true, diagnosticMode = "workspace", useLibraryCodeForTypes = true } } },
          })
        end,
      })

      vim.api.nvim_create_autocmd("BufReadPost", {
        callback = function()
          local mark = vim.api.nvim_buf_get_mark(0, '"')
          local lcount = vim.api.nvim_buf_line_count(0)
          if mark[1] > 0 and mark[1] <= lcount then
            pcall(vim.api.nvim_win_set_cursor, 0, mark)
          end
        end,
      })

      local function force_close()
        local listed_buffers = vim.fn.getbufinfo({buflisted = 1})
        if #listed_buffers <= 1 then vim.cmd("quit!") else vim.cmd("bdelete!") end
      end

      vim.keymap.set('n', '<leader>x', force_close, { desc = "Force Close" })
      vim.keymap.set('n', '<leader>e', function() require('yazi').yazi() end, { desc = "Yazi" })
      vim.keymap.set('n', '<Tab>', '<Cmd>BufferLineCycleNext<CR>', { desc = "Next Buf" })
      vim.keymap.set('n', '<S-Tab>', '<Cmd>BufferLineCyclePrev<CR>', { desc = "Prev Buf" })
      vim.keymap.set('n', '<leader>f', function() require("conform").format({ lsp_fallback = true }) end, { desc = "Format" })

      vim.api.nvim_create_autocmd('LspAttach', {
        callback = function(args)
          local opts = { buffer = args.buf }
          vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
          vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
          vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, opts)
          vim.keymap.set('n', '<leader>d', vim.diagnostic.open_float, opts)
        end,
      })
    '';
  };
}

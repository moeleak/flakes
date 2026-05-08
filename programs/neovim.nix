{ pkgs, inputs, ... }:

inputs.nixvim.legacyPackages.${pkgs.stdenv.hostPlatform.system}.makeNixvimWithModule {
  inherit pkgs;

  module =
    { lib, ... }:
    let
      inherit (lib.nixvim) mkRaw;
    in
    {
      viAlias = true;
      vimAlias = true;
      withRuby = true;
      withPython3 = true;

      extraPackages = with pkgs; [
        ripgrep
        statix
      ];

      globals.mapleader = " ";

      opts = {
        expandtab = true;
        shiftwidth = 2;
        tabstop = 2;
        number = true;
        relativenumber = true;
        ignorecase = true;
        smartcase = true;
        termguicolors = true;
        showmode = false;
        cursorline = true;
        clipboard = "unnamedplus";
        undofile = true;
      };

      colorschemes.catppuccin = {
        enable = true;
        settings = {
          flavour = "mocha";
          transparent_background = true;
          term_colors = true;
          integrations = {
            cmp = false;
            blink_cmp = {
              enabled = true;
              style = "bordered";
            };
            gitsigns = true;
            treesitter = true;
          };
        };
      };

      diagnostic.settings = {
        virtual_text = {
          prefix = "●";
          spacing = 4;
          format = mkRaw ''
            function(diagnostic)
              local max_width = 50
              local message = diagnostic.message:gsub("\n", " ")
              if #message > max_width then
                return string.sub(message, 1, max_width) .. "..."
              end
              return message
            end
          '';
        };
        underline = true;
        update_in_insert = true;
        severity_sort = true;
        signs.text = {
          "__rawKey__vim.diagnostic.severity.ERROR" = " ";
          "__rawKey__vim.diagnostic.severity.WARN" = " ";
          "__rawKey__vim.diagnostic.severity.HINT" = " ";
          "__rawKey__vim.diagnostic.severity.INFO" = " ";
        };
      };

      autoCmd = [
        {
          event = "BufReadPost";
          desc = "Restore cursor position";
          callback = mkRaw ''
            function()
              local mark = vim.api.nvim_buf_get_mark(0, '"')
              local lcount = vim.api.nvim_buf_line_count(0)
              if mark[1] > 0 and mark[1] <= lcount then
                pcall(vim.api.nvim_win_set_cursor, 0, mark)
              end
            end
          '';
        }
      ];

      keymaps = [
        {
          mode = "n";
          key = "<leader>x";
          action = mkRaw ''
            function()
              local listed_buffers = vim.fn.getbufinfo({ buflisted = 1 })
              if #listed_buffers <= 1 then
                vim.cmd("quit!")
              else
                vim.cmd("bdelete!")
              end
            end
          '';
          options.desc = "Force Close";
        }
        {
          mode = "n";
          key = "<leader>e";
          action = mkRaw ''function() require("yazi").yazi() end'';
          options.desc = "Yazi";
        }
        {
          mode = "n";
          key = "<Tab>";
          action = "<Cmd>BufferLineCycleNext<CR>";
          options.desc = "Next Buf";
        }
        {
          mode = "n";
          key = "<S-Tab>";
          action = "<Cmd>BufferLineCyclePrev<CR>";
          options.desc = "Prev Buf";
        }
        {
          mode = "n";
          key = "<leader>f";
          action = mkRaw ''function() require("conform").format({ lsp_format = "fallback" }) end'';
          options.desc = "Format";
        }
      ]
      ++ (map (i: {
        mode = "n";
        key = "<leader>${toString i}";
        action = "<Cmd>BufferLineGoToBuffer ${toString i}<CR>";
        options.desc = "Go to buffer ${toString i}";
      }) (lib.range 1 9));

      lsp = {
        luaConfig.pre = ''
          local original_show_message = vim.lsp.handlers["window/showMessage"]
          vim.lsp.handlers["window/showMessage"] = function(err, result, ctx, config)
            local client = ctx and ctx.client_id and vim.lsp.get_client_by_id(ctx.client_id)
            if client and client.name == "rust-analyzer" and result and result.message then
              if result.message:match("^Failed to discover workspace") then
                return
              end
            end
            return original_show_message(err, result, ctx, config)
          end
        '';

        keymaps = [
          {
            mode = "n";
            key = "gd";
            lspBufAction = "definition";
            options.desc = "Definition";
          }
          {
            mode = "n";
            key = "K";
            lspBufAction = "hover";
            options.desc = "Hover";
          }
          {
            mode = "n";
            key = "<leader>rn";
            lspBufAction = "rename";
            options.desc = "Rename";
          }
          {
            mode = "n";
            key = "<leader>d";
            action = mkRaw "vim.diagnostic.open_float";
            options.desc = "Diagnostic";
          }
        ];

        servers = {
          "*".config.capabilities = mkRaw "require('blink-cmp').get_lsp_capabilities()";

          nixd = {
            enable = true;
            config = {
              cmd = [ "nixd" ];
              filetypes = [ "nix" ];
              root_markers = [
                "flake.nix"
                ".git"
              ];
              settings.nixd.formatting.command = [ "nixfmt" ];
            };
          };

          clangd = {
            enable = true;
            config = {
              cmd = [ "clangd" ];
              filetypes = [
                "c"
                "cpp"
                "objc"
                "objcpp"
              ];
              root_markers = [
                "compile_commands.json"
                ".git"
              ];
              handlers."textDocument/publishDiagnostics" = mkRaw ''
                function(err, result, ctx, config)
                  if result and result.uri then
                    local filename = vim.uri_to_fname(result.uri)
                    if filename:match("%.h$") or filename:match("%.hpp$") then
                      if ctx and ctx.client_id and vim.lsp.diagnostic and vim.lsp.diagnostic.get_namespace then
                        vim.diagnostic.reset(vim.lsp.diagnostic.get_namespace(ctx.client_id), vim.uri_to_bufnr(result.uri))
                      end
                      return
                    end
                  end

                  return vim.lsp.handlers["textDocument/publishDiagnostics"](err, result, ctx, config)
                end
              '';
            };
          };

          pyright = {
            enable = true;
            config = {
              cmd = [
                "pyright-langserver"
                "--stdio"
              ];
              filetypes = [ "python" ];
              root_markers = [
                "pyproject.toml"
                "setup.py"
                "requirements.txt"
                ".git"
              ];
              settings.python.analysis = {
                autoSearchPaths = true;
                diagnosticMode = "workspace";
                useLibraryCodeForTypes = true;
              };
            };
          };

          rust_analyzer = {
            enable = true;
            config = {
              cmd = [ "rust-analyzer" ];
              filetypes = [ "rust" ];
              root_markers = [
                "Cargo.toml"
                "rust-project.json"
                ".git"
              ];
            };
          };
        };
      };

      plugins = {
        treesitter = {
          enable = true;
          settings = {
            highlight = {
              enable = true;
              additional_vim_regex_highlighting = false;
            };
            indent.enable = true;
          };
        };

        gitsigns = {
          enable = true;
          settings = {
            signcolumn = false;
            current_line_blame = true;
            current_line_blame_opts = {
              delay = 300;
              virt_text_pos = "eol";
            };
          };
        };

        bufferline = {
          enable = true;
          settings.options = {
            mode = "buffers";
            style_preset = mkRaw "require('bufferline').style_preset.default";
            separator_style = "thin";
            indicator.style = "none";
            numbers = "ordinal";
            diagnostics = "nvim_lsp";
            diagnostics_indicator = mkRaw ''
              function(count, level)
                return " " .. (level:match("error") and " " or " ") .. count
              end
            '';
            offsets = [
              {
                filetype = "NvimTree";
                text = "Explorer";
                text_align = "left";
                separator = true;
              }
            ];
            get_element_icon = mkRaw ''
              function(element)
                local icon, hl = require('nvim-web-devicons').get_icon_by_filetype(element.filetype, { default = false })
                return icon, hl
              end
            '';
          };
        };

        lualine = {
          enable = true;
          settings = {
            options = {
              theme = "auto";
              component_separators = {
                left = "";
                right = "";
              };
              section_separators = {
                left = "";
                right = "";
              };
              globalstatus = true;
            };
            sections = {
              lualine_a = [ "mode" ];
              lualine_b = [
                "branch"
                "diff"
                "diagnostics"
              ];
              lualine_c = [ "filename" ];
              lualine_x = [
                "encoding"
                "fileformat"
                "filetype"
              ];
              lualine_y = [ "progress" ];
              lualine_z = [ "location" ];
            };
          };
        };

        web-devicons.enable = true;
        nvim-autopairs.enable = true;

        yazi = {
          enable = true;
          settings = {
            open_for_directories = false;
            keymaps.show_help = "<f1>";
            hooks.yazi_opened = mkRaw ''
              function(_, buffer, _)
                vim.keymap.set('t', '<Esc>', '<C-\\><C-n>:close<CR>', { buffer = buffer })
              end
            '';
          };
        };

        conform-nvim = {
          enable = true;
          autoInstall.enable = true;
          settings = {
            formatters_by_ft = {
              nix = [ "nixfmt" ];
              cpp = [ "clang_format" ];
              c = [ "clang_format" ];
              python = [ "black" ];
              rust = [ "rustfmt" ];
            };
            format_on_save = {
              timeout_ms = 2000;
              lsp_format = "fallback";
            };
          };
        };

        luasnip.enable = true;
        blink-cmp = {
          enable = true;
          setupLspCapabilities = false;
          settings = {
            keymap = {
              preset = "enter";
              "<C-b>" = [
                "scroll_documentation_up"
                "fallback"
              ];
              "<C-f>" = [
                "scroll_documentation_down"
                "fallback"
              ];
              "<C-Space>" = [
                "show"
                "show_documentation"
                "hide_documentation"
              ];
              "<C-p>" = [
                "select_prev"
                "fallback"
              ];
              "<C-n>" = [
                "select_next"
                "fallback"
              ];
              "<Tab>" = [
                "snippet_forward"
                "fallback"
              ];
              "<S-Tab>" = [
                "select_prev"
                "snippet_backward"
                "fallback"
              ];
            };
            completion = {
              list.selection = {
                preselect = true;
                auto_insert = false;
              };
              menu = {
                max_height = 10;
                border = "rounded";
                draw.columns = [
                  [ "kind_icon" ]
                  {
                    __unkeyed-1 = "label";
                    __unkeyed-2 = "label_description";
                    gap = 1;
                  }
                ];
              };
              documentation = {
                auto_show = false;
                window.border = "rounded";
              };
              accept.auto_brackets.enabled = true;
            };
            snippets = {
              preset = "luasnip";
              score_offset = -3;
            };
            sources = {
              default = [
                "lsp"
                "snippets"
                "path"
              ];
              providers = {
                lsp = {
                  max_items = 10;
                  fallbacks = [ ];
                };
                snippets = {
                  max_items = 5;
                };
                path.score_offset = 3;
              };
            };
            cmdline.sources = [ ];
            appearance = {
              nerd_font_variant = "normal";
              kind_icons = {
                Text = "󰉿";
                Method = "󰊕";
                Function = "󰊕";
                Constructor = "󰒓";
                Field = "󰜢";
                Variable = "󰆦";
                Property = "󰖷";
                Class = "󱡠";
                Interface = "󱡠";
                Struct = "󱡠";
                Module = "󰅩";
                Unit = "󰪚";
                Value = "󰦨";
                Enum = "󰦨";
                EnumMember = "󰦨";
                Keyword = "󰻾";
                Constant = "󰏿";
                Snippet = "󱄽";
                Color = "󰏘";
                File = "󰈔";
                Reference = "󰬲";
                Folder = "󰉋";
                Event = "󱐋";
                Operator = "󰪚";
                TypeParameter = "󰬛";
              };
            };
            signature.enabled = true;
          };
        };
      };
    };
}

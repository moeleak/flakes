{ pkgs, inputs, ... }:

let
  # Keep target-specific workarounds out of the editor configuration below.
  platform =
    let
      inherit (pkgs.stdenv) buildPlatform hostPlatform;
      isCross = buildPlatform.system != hostPlatform.system;
      needsLp4aWorkarounds = isCross && hostPlatform.isRiscV64;
    in
    {
      nixvim =
        inputs.nixvim.legacyPackages.${hostPlatform.system}
          or inputs.nixvim.legacyPackages.${buildPlatform.system};

      lualine =
        if isCross then
          pkgs.vimUtils.buildVimPlugin {
            pname = "lualine.nvim";
            inherit (pkgs.vimPlugins.lualine-nvim) version src;
          }
        else
          pkgs.vimPlugins.lualine-nvim;

      # nixfmt and rustfmt are unavailable when cross-compiling for lp4a.
      formatterCommands =
        if needsLp4aWorkarounds then
          { nix = "alejandra"; }
        else
          {
            nix = "nixfmt";
            rust = "rustfmt";
          };
    };
in
platform.nixvim.makeNixvimWithModule {
  inherit pkgs;

  module =
    { lib, ... }:
    let
      inherit (lib.nixvim)
        listToUnkeyedAttrs
        mkRaw
        toRawKeys
        ;

      mkNormalMap = key: action: desc: {
        mode = "n";
        inherit key action;
        options = { inherit desc; };
      };

      mkLspMap = key: lspBufAction: desc: {
        mode = "n";
        inherit key lspBufAction;
        options = { inherit desc; };
      };

      closeBuffer = mkRaw ''
        function()
          local listed_buffers = vim.fn.getbufinfo({ buflisted = 1 })
          if #listed_buffers <= 1 then
            vim.cmd("quit!")
          else
            vim.cmd("bdelete!")
          end
        end
      '';

      toggleDiagnostics = mkRaw ''
        function()
          local enabled = vim.g.diagnostics_enabled
          if enabled == nil then
            enabled = not (vim.diagnostic.is_enabled and vim.diagnostic.is_enabled() == false)
          end

          vim.g.diagnostics_enabled = not enabled
          vim.diagnostic.enable(not enabled)
        end
      '';

      bufferKeymaps =
        lib.range 1 9
        |> map (
          index:
          let
            buffer = toString index;
          in
          mkNormalMap "<leader>${buffer}" "<Cmd>BufferLineGoToBuffer ${buffer}<CR>" "Go to buffer ${buffer}"
        );

      withFallback = action: [
        action
        "fallback"
      ];

      completionLabelColumn =
        listToUnkeyedAttrs [
          "label"
          "label_description"
        ]
        // {
          gap = 1;
        };
    in
    {
      viAlias = true;
      vimAlias = true;
      enableMan = false;
      withRuby = true;
      withPython3 = true;

      extraPackages = [
        pkgs.ripgrep
        pkgs.statix
      ];

      globals.mapleader = " ";

      opts = {
        number = true;
        relativenumber = true;
        cursorline = true;
        showmode = false;
        termguicolors = true;

        expandtab = true;
        shiftwidth = 2;
        tabstop = 2;

        ignorecase = true;
        smartcase = true;

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
        signs.text = toRawKeys {
          "vim.diagnostic.severity.ERROR" = " ";
          "vim.diagnostic.severity.WARN" = " ";
          "vim.diagnostic.severity.HINT" = " ";
          "vim.diagnostic.severity.INFO" = " ";
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
        (mkNormalMap "<leader>x" closeBuffer "Force Close")
        (mkNormalMap "<leader>e" (mkRaw ''function() require("yazi").yazi() end'') "Yazi")
        (mkNormalMap "<Tab>" "<Cmd>BufferLineCycleNext<CR>" "Next Buf")
        (mkNormalMap "<S-Tab>" "<Cmd>BufferLineCyclePrev<CR>" "Prev Buf")
        (mkNormalMap "<leader>f"
          (mkRaw ''function() require("conform").format({ lsp_format = "fallback" }) end'')
          "Format"
        )
        (mkNormalMap "<leader>c" toggleDiagnostics "Toggle Diagnostics")
      ]
      ++ bufferKeymaps;

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
          (mkLspMap "gd" "definition" "Definition")
          (mkLspMap "K" "hover" "Hover")
          (mkLspMap "<leader>rn" "rename" "Rename")
          (mkNormalMap "<leader>d" (mkRaw "vim.diagnostic.open_float") "Diagnostic")
        ];

        servers =
          {
            "*".capabilities = mkRaw "require('blink-cmp').get_lsp_capabilities()";

            nixd = {
              cmd = [ "nixd" ];
              filetypes = [ "nix" ];
              root_markers = [
                "flake.nix"
                ".git"
              ];
              settings.nixd.formatting.command = [ platform.formatterCommands.nix ];
            };

            clangd = {
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

            pyright = {
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

            rust_analyzer = {
              cmd = [ "rust-analyzer" ];
              filetypes = [ "rust" ];
              root_markers = [
                "Cargo.toml"
                "rust-project.json"
                ".git"
              ];
            };
          }
          |> builtins.mapAttrs (
            _: config: {
              enable = true;
              inherit config;
            }
          );
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
          package = platform.lualine;
          settings.options.globalstatus = true;
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
              nix = [ platform.formatterCommands.nix ];
              c = [ "clang_format" ];
              cpp = [ "clang_format" ];
              python = [ "black" ];
            }
            // lib.optionalAttrs (platform.formatterCommands ? rust) {
              rust = [ platform.formatterCommands.rust ];
            };
            formatters.clang_format.append_args = [
              "--style={SortIncludes: Never}"
            ];
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
              "<C-b>" = withFallback "scroll_documentation_up";
              "<C-f>" = withFallback "scroll_documentation_down";
              "<C-Space>" = [
                "show"
                "show_documentation"
                "hide_documentation"
              ];
              "<C-p>" = withFallback "select_prev";
              "<C-n>" = withFallback "select_next";
              "<Tab>" = withFallback "snippet_forward";
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
                  completionLabelColumn
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
                snippets.max_items = 5;
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

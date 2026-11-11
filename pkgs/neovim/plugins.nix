{ lib, pkgs, ... }:

let
  inherit (lib.nixvim) mkRaw;
  platform = import ./platform.nix pkgs;
in
{
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
  };
}

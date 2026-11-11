# Editor options, colours, diagnostics display and autocommands.
{ lib, pkgs, ... }:

let
  inherit (lib.nixvim) mkRaw toRawKeys;
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
}

{ lib, ... }:

let
  inherit (lib.nixvim) listToUnkeyedAttrs;

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
  plugins = {
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
}

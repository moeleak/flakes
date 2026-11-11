{ lib, ... }:

let
  inherit (lib.nixvim) mkRaw;

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

  bufferKeymaps = map (
    index:
    let
      buffer = toString index;
    in
    mkNormalMap "<leader>${buffer}" "<Cmd>BufferLineGoToBuffer ${buffer}<CR>" "Go to buffer ${buffer}"
  ) (lib.range 1 9);
in
{
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

  lsp.keymaps = [
    (mkLspMap "gd" "definition" "Definition")
    (mkLspMap "K" "hover" "Hover")
    (mkLspMap "<leader>rn" "rename" "Rename")
    (mkNormalMap "<leader>d" (mkRaw "vim.diagnostic.open_float") "Diagnostic")
  ];
}

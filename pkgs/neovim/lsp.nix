# Language servers. Their keymaps are in keymaps.nix.
{ lib, pkgs, ... }:

let
  inherit (lib.nixvim) mkRaw;
  platform = import ./platform.nix pkgs;
in
{
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

    servers =
      builtins.mapAttrs
        (_: config: {
          enable = true;
          inherit config;
        })
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
            cmd = platform.clangdCommand;
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
        };
  };
}

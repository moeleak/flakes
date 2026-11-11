# Neovim, configured with nixvim and built as an ordinary package:
#   import ./pkgs/neovim { inherit pkgs inputs; }
{ pkgs, inputs }:

let
  inherit (pkgs.stdenv) buildPlatform hostPlatform;
  # nixvim has no package set for a cross-compiled target; use the builder's.
  nixvim =
    inputs.nixvim.legacyPackages.${hostPlatform.system}
      or inputs.nixvim.legacyPackages.${buildPlatform.system};
in
nixvim.makeNixvimWithModule {
  inherit pkgs;

  module.imports = [
    ./options.nix
    ./keymaps.nix
    ./lsp.nix
    ./plugins.nix
    ./completion.nix
  ];
}

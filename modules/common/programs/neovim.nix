# Neovim (pkgs/neovim, configured with nixvim) as the system editor.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.programs.neovim;
in
{
  options.my.programs.neovim = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = { };
  };

  config = lib.mkIf (cfg != null) {
    environment.systemPackages = [
      (import ../../../pkgs/neovim { inherit pkgs inputs; })
    ];
    environment.variables.EDITOR = "nvim";
  };
}

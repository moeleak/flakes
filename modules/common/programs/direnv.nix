{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.programs.direnv;
in
{
  options.my.programs.direnv = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = if config.my.home != null then { } else null;
  };

  config = lib.mkIf (cfg != null) {
    home-manager.users.${config.my.user} = {
      home.packages = [ pkgs.direnv ];

      programs.direnv.enable = true;
      programs.direnv.nix-direnv.enable = true;
      programs.devenv.enable = true;
    };
  };
}

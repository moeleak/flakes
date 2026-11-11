{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.programs.steam;
in
{
  options.my.programs.steam = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = if config.my.variant == "desktop" then { } else null;
  };

  config = lib.mkIf (cfg != null) {
    programs.steam = {
      enable = true;
      fontPackages = with pkgs; [ source-han-sans ];
    };
  };
}

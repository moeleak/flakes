{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.system.xkb;
in
{
  options.my.system.xkb = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = if config.my.variant == "desktop" then { } else null;
  };

  config = lib.mkIf (cfg != null) {
    services.xserver.xkb = {
      layout = "us";
      variant = "";
    };
  };
}

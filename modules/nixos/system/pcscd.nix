{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.system.pcscd;
in
{
  options.my.system.pcscd = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = if config.my.variant == "desktop" then { } else null;
  };

  config = lib.mkIf (cfg != null) {
    services.pcscd.enable = true;
  };
}

{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.system.bluetooth;
in
{
  options.my.system.bluetooth = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = if config.my.variant == "desktop" then { } else null;
  };

  config = lib.mkIf (cfg != null) {
    hardware.bluetooth.enable = true;
  };
}

{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.system.oomd;
in
{
  options.my.system.oomd = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = null;
  };

  config = lib.mkIf (cfg != null) {
    systemd.services.systemd-oomd.enable = true;
  };
}

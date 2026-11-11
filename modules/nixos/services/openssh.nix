{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.openssh;
in
{
  options.my.services.openssh = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = if config.my.variant == "desktop" then { } else null;
  };

  config = lib.mkIf (cfg != null) {
    services.openssh.enable = true;
  };
}

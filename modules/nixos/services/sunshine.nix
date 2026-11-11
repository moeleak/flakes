{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.sunshine;
in
{
  options.my.services.sunshine = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = null;
  };

  config = lib.mkIf (cfg != null) {
    services.sunshine = {
      enable = true;
      autoStart = true; # optional: starts Sunshine automatically on login
      capSysAdmin = true;
    };
    services.sunshine.package = pkgs.sunshine.override {
      cudaSupport = true;
      cudaPackages = pkgs.cudaPackages;
    };
  };
}

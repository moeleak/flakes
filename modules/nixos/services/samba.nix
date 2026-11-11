{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.services.samba;
in
{
  options.my.services.samba = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = null;
  };

  config = lib.mkIf (cfg != null) {
    services.samba = {
      enable = true;
      settings = {
        Share = {
          path = "/home/moeleak/Share";
          browseable = true;
          writable = true;
          guestOk = true;
        };
      };
    };
  };
}

{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.programs.gnupg;
in
{
  options.my.programs.gnupg = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = if config.my.variant == "desktop" then { } else null;
  };

  config = lib.mkIf (cfg != null) {
    programs.gnupg.agent = {
      enable = true;
      pinentryPackage = lib.mkForce pkgs.pinentry-qt;
    };
  };
}

{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.programs.rime;
in
{
  options.my.programs.rime = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = if config.my.variant == "desktop" then { } else null;
  };

  config = lib.mkIf (cfg != null) {
    i18n.inputMethod = {
      enable = true;
      type = "fcitx5";
      fcitx5.waylandFrontend = true;
      fcitx5.addons = with pkgs; [
        rime-data
        fcitx5-rime
        fcitx5-gtk
      ];
    };
  };
}

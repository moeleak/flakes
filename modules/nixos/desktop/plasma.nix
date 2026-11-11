{
  config,
  inputs,
  lib,
  ...
}:
let
  cfg = config.my.desktop.plasma;
in
{
  options.my.desktop.plasma = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = null;
  };

  config = lib.mkIf (cfg != null) {
    services.xserver.enable = true;
    services.displayManager.sddm.enable = true;
    services.displayManager.sddm.wayland.enable = true;
    services.desktopManager.plasma6.enable = true;

    home-manager.users.${config.my.user} = lib.mkIf (config.my.home != null) {
      imports = [ inputs.plasma-manager.homeModules.plasma-manager ];

      programs.plasma = {
        enable = true;
        shortcuts = {
          "services/org.kde.spectacle.desktop"._launch = [ "Alt+@" ];
          "services/org.kde.spectacle.desktop".FullScreenScreenShot = [ "Alt+!" ];
          "services/org.kde.spectacle.desktop".ActiveWindowScreenShot = [ "Alt+#" ];
          "services/org.kde.krunner.desktop"._launch = [ "Meta+Space" ];
        };
        configFile = {
          kwinrc.Wayland = {
            InputMethod = {
              value = "/run/current-system/sw/share/applications/org.fcitx.Fcitx5.desktop";
              shellExpand = true;
            };
            VirtualKeyboardEnabled = true;
          };
        };
      };
    };
  };
}

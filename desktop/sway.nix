{
  config,
  lib,
  pkgs,
  ...
}:

let
  fcitx5Enabled =
    config.i18n.inputMethod.enable && config.i18n.inputMethod.type == "fcitx5";
in
lib.mkMerge [
  {
    programs.sway.enable = true;

    fonts.packages = lib.mkAfter [
      pkgs.nerd-fonts._0xproto
      pkgs.noto-fonts-cjk-sans
    ];

    home-manager.users.moeleak.programs.foot = {
      enable = true;
      package = pkgs.foot;
      settings = {
        main.font = "0xProto Nerd Font Mono:size=12";
      };
    };

    environment.etc."sway/config.d/20-touchpad.conf".text = ''
      input type:touchpad {
        natural_scroll enabled
      }
    '';

    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd sway";
          user = "greeter";
        };
      };
    };
  }

  (lib.mkIf fcitx5Enabled {
    programs.sway.extraSessionCommands = lib.mkAfter ''
      export XMODIFIERS=@im=fcitx
      export GTK_IM_MODULE=fcitx
      export QT_IM_MODULE=fcitx
      export SDL_IM_MODULE=fcitx
    '';

    environment.etc."sway/config.d/10-fcitx5.conf".text = ''
      exec ${config.i18n.inputMethod.package}/bin/fcitx5 -d --replace
      exec dbus-update-activation-environment --systemd XMODIFIERS GTK_IM_MODULE QT_IM_MODULE SDL_IM_MODULE
    '';
  })
]

# Fonts and graphical applications.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.packages.desktop;
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
in
{
  options.my.packages.desktop = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = if config.my.home != null && config.my.variant == "desktop" then { } else null;
  };

  config = lib.mkIf (cfg != null) {
    home-manager.users.${config.my.user} = {
      home.packages = [
        pkgs.ibm-plex
        pkgs.sarasa-gothic
        pkgs.source-han-serif
        pkgs.noto-fonts
        pkgs.noto-fonts-cjk-sans
        pkgs.nerd-fonts.jetbrains-mono
        pkgs.nerd-fonts._0xproto

        pkgs._64gram
        pkgs.thunderbird
        pkgs.pizarra-gpui
      ]
      ++ lib.optionals isLinux [
        pkgs.wemeet
        pkgs.wechat
        pkgs.libreoffice
        pkgs.audacious
        pkgs.moonlight-qt
        pkgs.hmcl
        pkgs.wl-clipboard
      ];

      # fcitx5 needs XMODIFIERS to type into WeChat
      xdg.dataFile."applications/wechat.desktop" = lib.mkIf isLinux {
        text = ''
          [Desktop Entry]
          Type=Application
          Name=Weixin
          Exec=env XMODIFIERS=@im=fcitx wechat %U
          Icon=wechat
        '';
      };
    };
  };
}

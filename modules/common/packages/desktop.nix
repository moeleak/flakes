# Fonts and graphical applications.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.my.packages.desktop;
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
  maltoriaLibraries = pkgs.callPackage ../../../pkgs/maltoria-libraries.nix { };
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
        pkgs.maltoria
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

      # Maltoria's Wine runtime where Maltoria keeps it, replaced whenever
      # its version differs: Maltoria downloads upstream's, for macOS 27 alone,
      # only into an empty Libraries or over an older one. What Maltoria
      # deploys into it (GPTK) it deploys again once it is replaced.
      home.activation.maltoriaLibraries = lib.mkIf isDarwin (
        inputs.home-manager.lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          target="$HOME/Library/Application Support/com.daydalek.Maltoria/Libraries"
          if ! cmp -s ${maltoriaLibraries}/Libraries/WhiskyWineVersion.plist "$target/WhiskyWineVersion.plist"; then
            run rm -rf "$target"
            run mkdir -p "$(dirname "$target")"
            run cp -R ${maltoriaLibraries}/Libraries "$target"
            run chmod -R u+w "$target"
          fi
        ''
      );

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

{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.system.fonts;
in
{
  options.my.system.fonts = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = if config.my.variant == "desktop" then { } else null;
  };

  config = lib.mkIf (cfg != null) {
    fonts = {
      packages = with pkgs; [
        noto-fonts
        noto-fonts-color-emoji
        noto-fonts-cjk-sans
        noto-fonts-cjk-serif
        source-code-pro
        hack-font
        jetbrains-mono
        wqy_zenhei
      ];
      fontDir.enable = true;
    };
    fonts.fontconfig = {
      defaultFonts = {
        emoji = [ "Noto Color Emoji" ];
        monospace = [
          "Noto Sans Mono"
          "Noto Sans Mono CJK SC"
          "Noto Sans Mono CJK TC"
          "Sarasa Mono SC"
          "DejaVu Sans Mono"
        ];
        sansSerif = [
          "Noto Sans"
          "Noto Sans CJK SC"
          "Noto Sans CJK TC"
          "Source Han Sans SC"
          "DejaVu Sans"
        ];
        serif = [
          "Noto Serif"
          "Noto Serif CJK SC"
          "Noto Serif CJK TC"
          "Source Han Serif SC"
          "DejaVu Serif"
        ];
      };
      cache32Bit = true; # For steam
    };
  };
}

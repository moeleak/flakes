# gal: run Windows galgames in a reproducible Wine prefix, ~/Games/Prefix/GalGame by default
# ($GALGAME_PREFIX overrides it). The prefix is created when missing, and the settings below are
# imported into it whenever they change; data written by the games (saves) is kept.
# `gal game.exe` runs a game with a Chinese locale (GBK code page), `gal` alone only prepares the prefix.
{
  lib,
  iconv,
  runCommand,
  writeShellApplication,
  writeText,
  wine,
}:

let
  # Fonts that Chinese, Japanese and Korean games ask for, replaced by installed ones
  # (sarasa-gothic and source-han-serif)
  fontReplacements = lib.concatMapAttrs (to: fonts: lib.genAttrs fonts (_: to)) {
    "Sarasa UI SC" = [
      "SimSun"
      "NSimSun"
      "SimHei"
      "Microsoft YaHei"
      "Microsoft YaHei UI"
      "宋体"
      "新宋体"
      "黑体"
      "微软雅黑"
    ];
    "Sarasa UI TC" = [
      "MingLiU"
      "PMingLiU"
      "Microsoft JhengHei"
      "細明體"
      "新細明體"
      "微軟正黑體"
    ];
    "Sarasa UI J" = [
      "MS Gothic"
      "MS PGothic"
      "MS UI Gothic"
      "Meiryo"
      "Meiryo UI"
      "ＭＳ ゴシック"
      "ＭＳ Ｐゴシック"
      "メイリオ"
    ];
    "Source Han Serif" = [
      "MS Mincho"
      "MS PMincho"
      "ＭＳ 明朝"
      "ＭＳ Ｐ明朝"
    ];
    "Sarasa UI K" = [
      "Gulim"
      "굴림"
    ];
    "Source Han Serif K" = [
      "Batang"
      "바탕"
    ];
  };

  # LOGFONTW as REG_BINARY, for the menu and message box fonts (ASCII face names only)
  logfont =
    {
      height,
      weight ? 400,
      charset ? 1, # DEFAULT_CHARSET
      face,
    }:
    let
      le32 = n: [
        (lib.mod n 256)
        (lib.mod (n / 256) 256)
        (lib.mod (n / 65536) 256)
        (n / 16777216)
      ];
      faceBytes = lib.concatMap (c: [
        (lib.strings.charToInt c)
        0
      ]) (lib.stringToCharacters face);
      bytes =
        le32 height
        ++ le32 0 # width
        ++ le32 0 # escapement
        ++ le32 0 # orientation
        ++ le32 weight
        ++ [
          0 # italic
          0 # underline
          0 # strike out
          charset
          0 # out precision
          0 # clip precision
          0 # quality
          0 # pitch and family
        ]
        ++ faceBytes
        ++ lib.genList (_: 0) (64 - lib.length faceBytes);
      hex = b: lib.fixedWidthString 2 "0" (lib.toLower (lib.toHexString b));
    in
    "hex:" + lib.concatMapStringsSep "," hex bytes;

  uiFont = logfont {
    height = 9;
    face = "Sarasa UI SC";
  };

  # The default value of Layers applies to every program in the prefix (a Wine extension):
  # "System (Enhanced)" GDI scaling, so that GDI text and menus are drawn at 200% instead of
  # being stretched. EmulateModeset makes Wine scale the windows of fullscreen games that change
  # the display mode, as Xwayland only fakes mode changes for the client that asked for them.
  regText = ''
    Windows Registry Editor Version 5.00

    [HKEY_CURRENT_USER\Control Panel\Desktop]
    "LogPixels"=dword:000000c0

    [HKEY_CURRENT_USER\Control Panel\Desktop\WindowMetrics]
    "MenuFont"=${uiFont}
    "MessageFont"=${uiFont}

    [HKEY_CURRENT_USER\Software\Wine\Fonts\Replacements]
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (from: to: ''"${from}"="${to}"'') fontReplacements)}

    [HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers]
    @="~ GDIDPISCALING DPIUNAWARE"

    [HKEY_CURRENT_USER\Software\Wine\X11 Driver]
    "EmulateModeset"="Y"
  '';

  # regedit reads non-ASCII names from UTF-16 files with a byte order mark
  reg = runCommand "galgame.reg" { nativeBuildInputs = [ iconv ]; } ''
    { printf '\xff\xfe'; iconv -f UTF-8 -t UTF-16LE ${writeText "galgame-utf8.reg" regText}; } > $out
  '';
in
writeShellApplication {
  name = "gal";
  runtimeInputs = [ wine ];
  text = ''
    export WINEPREFIX="''${GALGAME_PREFIX:-$HOME/Games/Prefix/GalGame}"
    export LANG=zh_CN.UTF-8
    stamp="$WINEPREFIX/.gal-settings"

    if [ ! -f "$WINEPREFIX/system.reg" ]; then
        echo "gal: creating $WINEPREFIX" >&2
        wineboot -i
    fi
    if [ "$(cat "$stamp" 2> /dev/null || true)" != "${reg}" ]; then
        echo "gal: applying the prefix settings" >&2
        wine regedit /S "$(winepath -w ${reg})"
        echo "${reg}" > "$stamp"
    fi

    if [ "$#" -gt 0 ]; then
        exec wine "$@"
    fi
  '';
}

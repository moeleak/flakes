# Windows galgames under Wine: the `gal` launcher (pkgs/gal.nix), an "Open with"
# entry that runs .exe files in its prefix, and the usual Wine tools.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.programs.galgame;

  # unstable is built from the moeleak/wine fork; the staging patches aren't checked against it
  wine = pkgs.wineWow64Packages.unstableFull;

  openWith = pkgs.writeTextDir "share/applications/wine-galgame.desktop" ''
    [Desktop Entry]
    Type=Application
    Name=GalGame（中文）
    Exec=gal start /unix %f
    MimeType=application/x-ms-dos-executable;application/x-msdownload;
    Icon=wine
    NoDisplay=true
  '';
in
{
  options.my.programs.galgame = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule { });
    default = if config.my.variant == "desktop" then { } else null;
  };

  config = lib.mkIf (cfg != null) {
    environment.systemPackages = [
      wine
      (pkgs.callPackage ../../../pkgs/gal.nix { inherit wine; })
      openWith
      pkgs.winetricks
      pkgs.bottles

      # video playback in games
      pkgs.gst_all_1.gstreamer
      pkgs.gst_all_1.gst-plugins-base
      pkgs.gst_all_1.gst-plugins-good
      pkgs.gst_all_1.gst-plugins-bad
      pkgs.gst_all_1.gst-plugins-ugly
      pkgs.gst_all_1.gst-libav
    ];
  };
}

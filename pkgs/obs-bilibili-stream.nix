{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
  obs-studio,
  qt6,
  curl,
  srcOverride ? null,
}:

stdenv.mkDerivation rec {
  pname = "obs-bilibili-stream";
  version = "2.1.6";

  src =
    if srcOverride != null then
      srcOverride
    else
      fetchFromGitHub {
        owner = "Zarosmm";
        repo = "obs-bilibili-stream";
        rev = version;
        hash = "sha256-WcoAqlBq45y3M4krx5hFeuNCxI88GsP287RBHmzEp5E=";
      };

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  buildInputs = [
    obs-studio
    qt6.qtbase
    curl
  ];

  # Plugin module, not a standalone Qt application.
  dontWrapQtApps = true;

  cmakeFlags = [
    "-DENABLE_FRONTEND_API=ON"
    "-DENABLE_QT=ON"
    "-DCMAKE_INSTALL_LIBDIR=lib"
  ];

  meta = with lib; {
    description = "OBS Studio plugin for streaming to Bilibili";
    homepage = "https://github.com/Zarosmm/obs-bilibili-stream";
    license = licenses.gpl2;
    platforms = platforms.linux;
  };
}

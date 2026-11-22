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

  # The plugin template's macOS build wants Xcode, and OBS's sources to build
  # libobs with; this one builds with Ninja against nixpkgs' obs-studio, and
  # makes no installer.
  postPatch = lib.optionalString stdenv.hostPlatform.isDarwin ''
    substituteInPlace cmake/macos/compilerconfig.cmake \
      --replace-fail 'if(NOT XCODE)' 'if(FALSE)' \
      --replace-fail 'check_sdk_requirements()' ""
    substituteInPlace cmake/macos/defaults.cmake \
      --replace-fail 'include(buildspec)' ""
    substituteInPlace cmake/macos/helpers.cmake \
      --replace-fail 'install(SCRIPT "''${CMAKE_CURRENT_BINARY_DIR}/create-package.cmake")' ""
  '';

  cmakeFlags = [
    "-DENABLE_FRONTEND_API=ON"
    "-DENABLE_QT=ON"
    "-DCMAKE_INSTALL_LIBDIR=lib"
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    "-DCMAKE_OSX_ARCHITECTURES=${stdenv.hostPlatform.darwinArch}"
    "-Dlibobs_DIR=${obs-studio}/Frameworks/libobs.framework/Resources/cmake"
    "-Dobs-frontend-api_DIR=${obs-studio}/lib/cmake/obs-frontend-api"
    # Which the template only sets in CI, and the bundle's properties need.
    "-DPLUGIN_BUILD_NUMBER=1"
    (lib.cmakeBool "CMAKE_COMPILE_WARNING_AS_ERROR" false)
  ];

  # The bundle, where wrapOBS puts darwin's plugins in OBS.app.
  postInstall = lib.optionalString stdenv.hostPlatform.isDarwin ''
    plugin=$(find $out -name '*.plugin' -type d -prune | head -1)
    mkdir -p $out/lib/obs-plugins
    mv "$plugin" $out/lib/obs-plugins/
    find $out -mindepth 1 -maxdepth 1 ! -name lib -exec rm -rf {} +
    find $out/lib -mindepth 1 -maxdepth 1 ! -name obs-plugins -exec rm -rf {} +
  '';

  meta = with lib; {
    description = "OBS Studio plugin for streaming to Bilibili";
    homepage = "https://github.com/Zarosmm/obs-bilibili-stream";
    license = licenses.gpl2;
    platforms = platforms.linux ++ platforms.darwin;
  };
}

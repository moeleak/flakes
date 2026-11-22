# Maltoria's Wine runtime ("Whisky Libraries"), from the moeleak fork of
# daydalek/ge-proton-macos-wine-poc that builds it for macOS 15: upstream's
# targets macOS 27 alone, and its Wine fails to load on older systems.
{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation {
  pname = "maltoria-libraries";
  # Newer than upstream's 11.0.N, so that Maltoria keeps it.
  version = "11.15.3";

  src = fetchurl {
    url = "https://github.com/moeleak/ge-proton-macos-wine-poc/releases/download/v0.1.12-macos15/Libraries.tar.gz";
    hash = "sha256-7ZaInxuIdhdAvREwPNYdZwlZLAtwSytstrl5NIEy4Ao=";
  };

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -a Libraries $out/
    runHook postInstall
  '';

  # Signed ad hoc, which patching would break.
  dontFixup = true;

  meta = {
    description = "Wine runtime for Maltoria, built for macOS 15";
    homepage = "https://github.com/moeleak/ge-proton-macos-wine-poc";
    license = lib.licenses.lgpl21Plus;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "aarch64-darwin" ];
  };
}

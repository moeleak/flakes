{
  autoPatchelfHook,
  buildGoModule,
  fetchFromGitHub,
  fetchurl,
  glibc,
  lib,
  stdenvNoCC,
}:

let
  # ChmlFrp is based on an old frp release that does not build with current Go.
  go_1_20_14 = stdenvNoCC.mkDerivation {
    pname = "go";
    version = "1.20.14";

    src = fetchurl {
      url = "https://go.dev/dl/go1.20.14.linux-amd64.tar.gz";
      hash = "sha256-/0ReSK8n+T9mvZSa4GDZeZHIPhEokAnTEfJUJiWPnEQ=";
    };

    sourceRoot = "go";
    nativeBuildInputs = [ autoPatchelfHook ];
    buildInputs = [ glibc ];

    dontBuild = true;
    dontStrip = true;

    passthru = {
      CGO_ENABLED = 1;
      GOARCH = "amd64";
      GOOS = "linux";
    };

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -a . "$out/"
      runHook postInstall
    '';
  };
in
(buildGoModule.override { go = go_1_20_14; }) rec {
  pname = "chmlfrp-frpc";
  version = "0.51.2-251023";

  src = fetchFromGitHub {
    owner = "TechCat-Team";
    repo = "ChmlFrp-Frp";
    rev = "9899607838eebd4bccd051dca885c9b0174ce182";
    hash = "sha256-BWndws/b943nt6eZrG1mOJVDuBeRQgVTQ7NriRAG2Tg=";
  };

  vendorHash = "sha256-QRLQk3Zew85mzeEH57ZHxt676+cPPIYTXfD21Zsb9x0=";
  subPackages = [ "cmd/frpc" ];

  meta = {
    description = "ChmlFrp-customized frp client";
    homepage = "https://github.com/TechCat-Team/ChmlFrp-Frp";
    license = lib.licenses.asl20;
    mainProgram = "frpc";
    platforms = [ "x86_64-linux" ];
  };
}
